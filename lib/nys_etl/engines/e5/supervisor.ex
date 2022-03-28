defmodule NYSETL.Engines.E5.Supervisor do
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def stop() do
    Supervisor.stop(__MODULE__, :normal, :infinity)
  end

  def init(_) do
    counties = NYSETL.Commcare.County.participating_counties()

    children = [
      NYSETL.Engines.E5.PollingConfig,
      Supervisor.child_spec(
        {
          NYSETL.Engines.E5.Broadway,
          county_list: counties
        },
        id: :"broadway.engines.e5"
      )
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
