defmodule ExBanking.Utils.Helpers do
  @moduledoc false

  alias ExBanking.Core.{Account, Transaction, Repo}
  alias ExBanking.Transactions.Serializer, as: Server
  alias ExBanking.Transactions.Supervisors.DynamicSerializerSupervisor, as: Sup

  @doc """
  Creates a new account for a given user is they don't exist
  """
  def do_create_account(user) do
    with account <- Account.new(user), {:ok, %Account{}} <- Repo.insert_account(account), do: :ok
  end

  @doc """
  Performs the actual transaction for a given user
  """
  def do_transaction(type, user, amount, currency) do
    with {:ok, acc} <- get_account(user),
         {:ok, params} <- transaction_params(type, acc, amount, currency),
         {:ok, trans} <- Transaction.for_user(params),
         {:ok, balance} <- commit_transaction(acc, trans),
         do: balance
  end

  # get the account from the repo
  defp get_account(user) do
    case Repo.get_account(user) do
      %Account{} = account ->
        {:ok, account}

      nil ->
        {:error, :user_does_not_exist}
    end
  end

  # returns the transaction params for deposit and withdrawal transactions
  defp transaction_params(type, account, amount, currency),
    do: {:ok, %{type: type, account: account, amount: amount, currency: currency}}

  # for each user's account, this function starts a process that will
  # be responsible for performing the transaction. If the process does not
  # exist, it starts it before committing the transaction
  defp commit_transaction(%Account{owner: user}, transaction) do
    Server.add_transaction(
      user: user,
      transaction: transaction,
      name: get_server_name(user)
    )
  end

  @doc """
  Performs a sending transaction.
  In case an error is returned when depositing the amount to
  the receiver, the withdrawal transaction from the sender is
  reversed.
  """
  def do_send_transaction(from_user, to_user, amount, currency) do
    with {:ok, sender_balance} <- do_sender_transaction(from_user, amount, currency),
         {:ok, rcv_balance} <- do_rcv_transaction(from_user, to_user, amount, currency) do
      {:ok, sender_balance, rcv_balance}
    end
  end

  # performs a withdrawal transaction from the sender of
  # the money
  defp do_sender_transaction(from_user, amount, currency) do
    case do_transaction(:withdrawal, from_user, amount, currency) do
      {:error, _reason} = error ->
        translate_sender_error(error)

      balance ->
        {:ok, balance}
    end
  end

  # performs a deposit transaction for the receiver of the
  # money. If an error occurs, it initiates a reversal of
  # the withdrawal from the senders account.
  defp do_rcv_transaction(from_user, to_user, amount, currency) do
    case do_transaction(:deposit, to_user, amount, currency) do
      {:error, _reason} = error ->
        {:ok, _} = reverse_sender_transaction(from_user, amount, currency)
        translate_rcv_error(error)

      balance ->
        {:ok, balance}
    end
  end

  @doc """
  Get's the balance of the user from
  """
  def do_get_balance(user, currency) do
    with server_name <- get_server_name(user),
         {:ok, %Account{} = acc} <- Server.get_current_balance(name: server_name),
         {:ok, %Money{amount: amount}} <- Account.to_currency(acc, currency),
         {:ok, amount} <- {:ok, Decimal.to_float(amount)},
         do: {:ok, amount}
  end

  # for each of the user's account, it creates a new
  # serializer server to perform the user's transactions.
  # If the server had already been started, it returns the
  # registered name of that server, so it can be reused
  defp get_server_name(user) when is_binary(user) do
    case Sup.serializer_for_account(user) do
      {:via, _registry, _name} = name ->
        name

      :no_proc ->
        Sup.start_serializer(%{user: user})
    end
  end

  defp reverse_sender_transaction(from_user, amount, currency),
    do: do_transaction(:deposit, from_user, amount, currency)

  defp translate_rcv_error({:error, :user_does_not_exit}),
    do: {:error, :receiver_does_not_exist}

  defp translate_rcv_error({:error, :too_many_requests_for_user}),
    do: {:error, :too_many_requests_for_receiver}

  defp translate_sender_error({:error, :user_does_not_exit}), do: {:error, :sender_does_not_exist}

  defp translate_sender_error({:error, :too_many_requests_for_user}),
    do: {:error, :too_many_requests_for_sender}

  defp translate_sender_error(error), do: error
end
