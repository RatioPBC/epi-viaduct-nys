defmodule NYSETL.Engines.E1.FileReader do
  @moduledoc """
  Broadway producer to read an ECLRS file and message the state machine in State when
  the end of the file has been reached.
  """

  use GenStage
  alias NYSETL.ECLRS
  alias NYSETL.Engines.E1
  require Logger

  defstruct ~w{
    file
    file_handle
    file_headers
    line_count
  }a

  def new(attrs \\ []), do: __struct__(attrs)

  def start_link(file) do
    GenStage.start_link(__MODULE__, file)
  end

  def init(file) do
    :telemetry.execute([:extractor, :eclrs, :file_reader, :open], %{count: 1})
    {:ok, file_handle} = File.open(file.filename, [:read])

    headers = {eclrs_version, _header_names} =
      IO.read(file_handle, :line)
      |> String.trim()
      |> ECLRS.File.file_headers()

    {:ok, file} = ECLRS.update_file(file, %{eclrs_version: ECLRS.File.version_number(eclrs_version)})

    {:producer, new(file: file, file_handle: file_handle, line_count: 0, file_headers: headers)}
  end

  def handle_demand(demand, state) do
    events = read(state, demand)
    event_length = length(events)
    :telemetry.execute([:extractor, :eclrs, :file_reader, :read], %{count: event_length})
    if event_length < demand, do: fini()
    {:noreply, events, %{state | line_count: state.line_count + event_length}}
  end

  def handle_info(:fini, state) do
    E1.State.finish_reads(state.line_count)
    {:noreply, [], state}
  end

  defp fini(), do: send(self(), :fini)

  def read(%__MODULE__{file_headers: {version, _}, file_handle: handle}, line_count) do
    1..line_count
    |> Enum.map(fn _x ->
      IO.read(handle, :line)
    end)
    |> Enum.reject(fn line -> line == :eof end)
    |> Enum.map(fn line -> {version, String.trim(line)} end)
  end
end
