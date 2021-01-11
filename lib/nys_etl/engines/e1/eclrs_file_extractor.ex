defmodule NYSETL.Engines.E1.ECLRSFileExtractor do
  alias NYSETL.ECLRS
  alias NYSETL.Engines.E1

  def extract(filename) do
    {:ok, file} = ECLRS.create_file(%{filename: filename, processing_started_at: DateTime.utc_now()})
    {:ok, _pid} = E1.Supervisor.start_link(file)
    :ok
  end

  def extract!(filename) do
    :ok = extract(filename)
    {:ok, _state} = wait()
    E1.Supervisor.stop()
    :ok
  end

  def wait() do
    :timer.sleep(100)
    if finished?(), do: {:ok, E1.State.get()}, else: wait()
  end

  def finished?(), do: E1.State.finished?()
end
