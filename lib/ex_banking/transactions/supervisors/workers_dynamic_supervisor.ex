defmodule ExBanking.Transactions.Supervisors.WorkersDynamicSupervisor do
  @moduledoc """
  Defines a dynamic supervisor for starting the Worker process
  in charge of performing transactions on user accounts
  """
  use DynamicSupervisor, restart: :permanent

  alias ExBanking.Transactions.{Worker}

  @doc false
  @spec start_link(opts :: Keyword.t()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    DynamicSupervisor.start_link(__MODULE__, :undefined, name: name)
  end

  @doc """
  Starts a worker process that will perform a transaction
  """
  @spec start_worker(args :: map()) :: DynamicSupervisor.on_start_child()
  def start_worker(%{} = args) do
    opts = Keyword.new(args)

    DynamicSupervisor.start_child(__MODULE__, {Worker, opts})
  end

  @impl DynamicSupervisor
  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
