defmodule NYSETL.Engines.E3.Supervisor do
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def stop() do
    Supervisor.stop(__MODULE__, :normal, :infinity)
  end

  def init(_) do
    children = [
      NYSETL.Engines.E3.Broadway
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
