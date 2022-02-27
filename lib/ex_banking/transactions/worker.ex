defmodule ExBanking.Transactions.Worker do
  @moduledoc """
  This module is the worker process that will be responible for performing
  all the transaction tasks
  """
  use GenServer, restart: :transient, shutdown: 5000

  alias ExBanking.Core.{Repo}

  defstruct transaction: nil, user: nil, reply_to: nil

  @doc """
  Starts the server

  It is expected that the opts passed contains the following fields
  1.`:user` => will be used to passed to Repo.update_account/2
  2. `:transaction` => will be passed to the Repo.update_account/2
  3. `:reply_to` => the registered name of the transaction tracker process
                    where replies will be sent in order to notify it that
                    the transaction is complete.
  """
  @spec start_link(opts :: Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(opts) do
    # Here, we pass the opts directly as is because the details
    # will be used to perform the transaction
    {:ok, new_state(opts), {:continue, :perform_transaction}}
  end

  defp new_state(opts) do
    %__MODULE__{
      transaction: Keyword.fetch!(opts, :transaction),
      user: Keyword.fetch!(opts, :user),
      reply_to: Keyword.fetch!(opts, :reply_to)
    }
  end

  @impl GenServer
  def handle_continue(:perform_transaction, %__MODULE__{} = state) do
    %{
      transaction: transaction,
      user: user,
      reply_to: reply_to
    } = state

    Repo.update_account(user, transaction)

    # sending a message to the transaction tracker process is important
    # because that process will use this message perform the next transaction
    # in the queue
    send(reply_to, {:transaction_complete, transaction})

    # terminate normally
    {:stop, :normal, state}
  end

  @impl GenServer
  def terminate(:normal, _state), do: :ok
end
