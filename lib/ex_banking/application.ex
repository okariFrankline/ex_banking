defmodule ExBanking.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias ExBanking.Transactions.Supervisors.{DynamicSerializerSupervisor, WorkersDynamicSupervisor}

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, name: ExBanking.Transactions.SerializerRegistry, keys: :unique},
      WorkersDynamicSupervisor,
      DynamicSerializerSupervisor
    ]

    # define the ETS table
    :ets.new(:repo, [:named_table, :public])

    opts = [strategy: :one_for_one, name: ExBanking.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
