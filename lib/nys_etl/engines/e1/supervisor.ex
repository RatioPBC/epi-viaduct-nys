defmodule NYSETL.Engines.E1.Supervisor do
  use Supervisor

  alias NYSETL.ECLRS
  alias NYSETL.Engines.E1

  def start_link(%ECLRS.File{} = file) do
    Supervisor.start_link(__MODULE__, file, name: __MODULE__)
  end

  def stop() do
    Supervisor.stop(__MODULE__, :normal, :infinity)
  end

  def init(file) do
    children = [
      {E1.State, file},
      {E1.Broadway, file}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
