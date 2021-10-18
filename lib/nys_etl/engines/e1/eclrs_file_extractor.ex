defmodule NYSETL.Engines.E1.ECLRSFileExtractor do
  alias NYSETL.ECLRS
  alias NYSETL.Engines.E1
  alias NYSETL.Engines.E2.TestResultProducer

  def extract(filename) do
    {:ok, file} = ECLRS.create_file(%{filename: filename, processing_started_at: DateTime.utc_now()})
    {:ok, _pid} = E1.Supervisor.start_link(file)
    {:ok, file}
  end

  def extract!(filename) do
    {:ok, file} = extract(filename)
    {:ok, _state} = wait()
    E1.Supervisor.stop()
    TestResultProducer.new(%{"file_id" => file.id}) |> Oban.insert!()
    :ok
  end

  def wait() do
    :timer.sleep(100)
    if finished?(), do: {:ok, E1.State.get()}, else: wait()
  end

  def finished?(), do: E1.State.finished?()
end
