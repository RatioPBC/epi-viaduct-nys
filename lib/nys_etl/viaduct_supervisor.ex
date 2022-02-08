defmodule NYSETL.ViaductSupervisor do
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    children = [
      NYSETL.Commcare.Api.cache_spec(),
      {Oban, Application.get_env(:nys_etl, Oban)},
      NYSETL.Engines.E2.TestResultProducer,
      NYSETL.Engines.E5.Supervisor,
      NYSETL.Engines.E1.SQSTask
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
