defmodule ExBanking.Transactions.Supervisors.DynamicSerializerSupervisor do
  @moduledoc """
  This is dynamic supervisor that will be in charge of starting a
  sungle serializer for each user's account transaction.

  How it works
  ------------
  => Whenever a user wants to make a transaction, say a deposit. The system
    will query this supervisor to check whether or not, there is an active
    serializer process for that user.
  => If the process exists, it will return the pid/registered name and then the
    client will reuse the process for the new transactions.
  => However, if the process does not exist, this supervisor will start a new
    process and add the transaction to the process's queue and await a response.

  """
  use DynamicSupervisor, restart: :permanent

  alias ExBanking.Core.{Repo}

  alias ExBanking.Transactions.{Serializer, SerializerRegistry}

  @doc false
  @spec start_link(opts :: Keyword.t()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    DynamicSupervisor.start_link(__MODULE__, :undefined, name: name)
  end

  @doc """
  Starts a new serializer for each user's transaction.
  It expects a map argument with the following fields given:
  1. :user => the user for which the account belongs to
  2. :transaction => the transaction for which the account is to perform

  If the user account does not exist, it returns an error

  """
  @spec start_serializer(opts :: map()) ::
          {:via, Registry, String.t()} | {:error, :user_does_not_exist}
  def start_serializer(%{user: user} = args) do
    if Repo.account_exists?(user) do
      opts = Keyword.new(args)

      DynamicSupervisor.start_child(__MODULE__, {Serializer, opts})

      Serializer.via(user)
    else
      {:error, :user_does_not_exist}
    end
  end

  @doc """
  Checks to see whether a serializer process has been started for the
  given user account. It returns the registered name for the process

  ## Examples
      iex> serializer_for_account(user)
      {:via, SerializerRegistry, user}

      iex> serializer_for_account(non_existant_user)
      :no_proc

  """
  @spec serializer_for_account(user) :: {:via, atom() | module(), user} | :no_proc
        when user: String.t()
  def serializer_for_account(user) do
    case Registry.whereis_name({SerializerRegistry, user}) do
      pid when is_pid(pid) -> Serializer.via(user)
      :undefined -> :no_proc
    end
  end

  @impl DynamicSupervisor
  def init(_args) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: :timer.seconds(30)
    )
  end
end
