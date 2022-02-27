defmodule ExBanking.Transactions.Serializer do
  @moduledoc """
  This module process's function is to serialize all the
  transaction requests for a given account.
  """
  use GenServer, restart: :transient

  alias ExBanking.Core.{Account, Transaction, Repo}

  alias ExBanking.Transactions.SerializerRegistry

  alias ExBanking.Transactions.Supervisors.WorkersDynamicSupervisor

  defstruct pending_transactions: [],
            complete_transactions: [],
            clients_awaiting_balance: [],
            transaction_in_progress: nil,
            user: nil

  @timeout :timer.seconds(10)

  @doc """
  Starts the server.

  The options passed are expected to have the user
  for which this process will manage
  """
  @spec start_link(opts :: Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    user = Keyword.fetch!(opts, :user)

    GenServer.start_link(__MODULE__, opts, name: via(user))
  end

  @doc false
  def via(name) do
    {:via, SerializerRegistry, name}
  end

  @doc """
  Adds a new transaction to the serializer queue.
  This call is synchronous because the client has to know whether or not
  he/she has exceeded the number of transactions at a given time.
  """
  @spec add_transaction(opts :: Keyword.t()) :: :ok | :too_many_transactions
  def add_transaction(opts) do
    # the name here is expected to be {:via, Registry, name}
    name = Keyword.fetch!(opts, :name)

    GenServer.call(name, {:add_transaction, opts[:transaction]})
  end

  @spec get_current_balance(opts :: Keyword.t()) :: {:ok, Account.t()} | no_return()
  def get_current_balance(opts) do
    # the name here is expected to be {:via, Registry, name}
    name = Keyword.fetch!(opts, :name)

    GenServer.call(name, :get_current_balance)
  end

  @impl GenServer
  def init(opts) do
    {:ok, %__MODULE__{user: opts[:user]}, @timeout}
  end

  @impl GenServer
  def handle_call(
        {:add_transaction, %Transaction{} = transaction},
        from,
        %__MODULE__{clients_awaiting_balance: clients} = state
      ) do
    if can_add_another_transaction?(state) do
      new_state =
        state
        |> add_transaction(transaction)
        |> Map.update(:clients_awaiting_balance, clients, &[from | &1])

      {:noreply, new_state}
    else
      {:reply, {:error, :too_many_requests_to_user}, @timeout}
    end
  end

  @impl GenServer
  def handle_call(
        :get_current_balance,
        from,
        %__MODULE__{clients_awaiting_balance: clients} = state
      ) do
    # Here we check whether all the transactions have been completed
    # if they have, we read the balance from the db and return that
    # However, if not, we update the state by adding the client process
    # to the list of processes_awaiting response, so that the reply could
    # be sent later on, when all transactions are done
    if transactions_complete?(state) do
      %Account{} = account = Repo.get_account(state.user)

      {:reply, {:ok, account}, state, @timeout}
    else
      new_state =
        state
        |> Map.update(:clients_awaiting_balance, clients, &[from | &1])

      {:noreply, new_state}
    end
  end

  defp transactions_complete?(%__MODULE__{pending_transactions: [], transaction_in_progress: nil}),
    do: true

  defp transactions_complete?(%__MODULE__{} = _state), do: false

  # returns true | false if the total number of pending transactions
  # and the transaction in progress is < 10
  defp can_add_another_transaction?(%__MODULE__{
         pending_transactions: pending_transactions,
         transaction_in_progress: progress
       }) do
    in_progress = if progress, do: 1, else: 0

    length(pending_transactions) + in_progress > 10
  end

  # adds the transaction to the end of the list.
  # This is done to preserve the order in which the transactions have been
  # added, and also because we have a limit of 10 items in the list, it will
  # not be as expensive and operation.
  defp add_transaction(
         %__MODULE__{pending_transactions: p_transactions} = state,
         %Transaction{} = transaction
       ) do
    state
    |> Map.update(:pending_transactions, p_transactions, &(&1 ++ [transaction]))
  end

  @impl GenServer
  def handle_info({:transaction_complete, msg}, %__MODULE__{} = state) do
    # upon receiving a message for transaction complete, we update the
    # state to reflect the new state of the transactions and then
    # try to perform another transaction (Only of the list of pending
    # transactions is not [])
    state = update_state_after_transaction_completion(state, msg)

    {:noreply, maybe_perform_transaction(state), @timeout}
  end

  @impl GenServer
  def handle_info(
        :timeout,
        %__MODULE__{pending_transactions: [], transaction_in_progress: nil} = state
      ) do
    # only stop if there are no more transactions pending or
    # a transaction in progress
    {:stop, :normal, state}
  end

  def handle_info(:timeout, state) do
    {:noreply, state, @timeout}
  end

  # after a transaction is complete, this function will ensure that the
  # completed transaction is added to the list of completed transactions
  # and the transaction_in_progress is reset to nil. Essentially this function
  # ensure that the state is ready for another transaction being performed, if any
  defp update_state_after_transaction_completion(
         %__MODULE__{
           transaction_in_progress: {pid, transaction},
           complete_transactions: c_transactions
         } = state,
         {pid, transaction} = _msg
       ) do
    state
    |> Map.update(:complete_transactions, c_transactions, &[transaction | &1])
    |> Map.put(:transaction_in_progress, nil)
  end

  # checks to ensure that the pending transactions is empty or not
  # and based on that return the state as is or start another
  # worker process to perform the next transaction in the queue
  defp maybe_perform_transaction(
         %{
           transaction_in_progress: nil,
           pending_transactions: [],
           clients_waiting_balance: clients
         } = state
       ) do
    # When theere are not pending transactions or a transaction in progress, it means
    # that all the transactions are complete, as such, we just send the current
    # balance to the awaiting clients
    %Account{current_balance: balance} = Repo.get_account(state.user)

    for client <- clients, do: GenServer.reply(client, {:ok, balance})

    state
  end

  defp maybe_perform_transaction(state) do
    case get_worker_opts(state) do
      nil ->
        state

      %{} = opts ->
        start_worker_process(opts, state)
    end
  end

  # Based on whether the pending transactions is empty or not
  # it returns the arguments that will be used to start a new
  # worker process to perform a transaction
  defp get_worker_opts(%{pending_transactions: []}), do: nil

  defp get_worker_opts(%{user: user, pending_transactions: [transaction | _]}) do
    %{
      user: user,
      transaction: transaction,
      reply_to: self()
    }
  end

  # starts a new worker process to perform the next transaction in the
  # queue. It also update the pending transactions as well as the
  # transactions in progress
  defp start_worker_process(
         %{transaction: transaction} = opts,
         %__MODULE__{pending_transactions: [transaction | rest]} = state
       ) do
    {:ok, worker_pid} = WorkersDynamicSupervisor.start_worker(opts)

    state
    |> Map.put(:pending_transactions, rest)
    |> Map.put(:transaction_in_progress, {worker_pid, transaction})
  end
end
