defmodule NYSETL.Engines.E1.State do
  @moduledoc """
  Used as an Agent-based state machine for processing a single ECLRS file.
  """

  use Agent
  alias NYSETL.ECLRS
  require Logger

  @enforce_keys [:file]
  defstruct file: nil,
            line_count: 0,
            duplicate_records: %{total: 0},
            error_records: %{total: 0},
            matched_records: %{total: 0},
            new_records: %{total: 0},
            processed_count: 0,
            start_time: nil,
            status: :loading,
            updates: %{total: 0}

  def start_link(%ECLRS.File{} = file) do
    info("beginning test results extract from filename=#{file.filename}")
    Agent.start_link(fn -> new(file) end, name: __MODULE__)
  end

  def new(%ECLRS.File{} = file), do: __struct__(file: file, start_time: now())
  def get(), do: Agent.get(__MODULE__, fn state -> state end)

  def finish_reads(line_count) do
    Agent.update(__MODULE__, fn
      %{status: :finished} = state ->
        state

      %{processed_count: processed} = state when processed == line_count ->
        %{state | status: :finished, line_count: line_count}

      state ->
        %{state | status: :read_complete, line_count: line_count}
    end)
  end

  def finished?(), do: status() == :finished

  def fini() do
    Agent.update(__MODULE__, fn state ->
      info("finished test results extracting from filename=#{state.file.filename}")
      :telemetry.execute([:broadway, :pipeline, :process], %{time: now() - state.start_time}, %{})

      ECLRS.finish_processing_file(state.file,
        statistics: %{
          duplicate: state.duplicate_records,
          error: state.error_records,
          matched: state.matched_records,
          new: state.new_records
        }
      )

      %{state | status: :finished}
    end)
  end

  def status(), do: Agent.get(__MODULE__, fn state -> state.status end)
  def update_duplicate_count(values), do: Agent.update(__MODULE__, &with_duplicate_counts(&1, values))
  def update_error_count(values), do: Agent.update(__MODULE__, &with_error_counts(&1, values))
  def update_matched_count(values), do: Agent.update(__MODULE__, &with_matched_counts(&1, values))
  def update_new_count(values), do: Agent.update(__MODULE__, &with_new_counts(&1, values))

  def update_processed_count(count) do
    Agent.get_and_update(__MODULE__, fn state ->
      processed_count = state.processed_count + count
      state = %{state | processed_count: processed_count}
      {state, state}
    end)
    |> case do
      %{status: :read_complete, line_count: count, processed_count: count} -> fini()
      _ -> :ok
    end
  end

  defp info(msg), do: Logger.info("[#{__MODULE__}] #{msg}")
  defp now(), do: DateTime.utc_now() |> DateTime.to_unix(:millisecond)

  defp with_duplicate_counts(%__MODULE__{} = state, values) do
    summaries =
      values
      |> Enum.reduce(state.duplicate_records, fn {county_id, count}, acc ->
        acc
        |> Map.update(county_id, count, &(&1 + count))
        |> Map.update(:total, count, &(&1 + count))
      end)

    %{state | duplicate_records: summaries}
  end

  defp with_error_counts(%__MODULE__{} = state, values) do
    summaries =
      values
      |> Enum.reduce(state.error_records, fn {county_id, count}, acc ->
        acc
        |> Map.update(county_id, count, &(&1 + count))
        |> Map.update(:total, count, &(&1 + count))
      end)

    %{state | error_records: summaries}
  end

  defp with_matched_counts(%__MODULE__{} = state, values) do
    summaries =
      values
      |> Enum.reduce(state.matched_records, fn {county_id, count}, acc ->
        acc
        |> Map.update(county_id, count, &(&1 + count))
        |> Map.update(:total, count, &(&1 + count))
      end)

    %{state | matched_records: summaries}
  end

  defp with_new_counts(%__MODULE__{} = state, values) do
    summaries =
      values
      |> Enum.reduce(state.new_records, fn {county_id, count}, acc ->
        acc
        |> Map.update(county_id, count, &(&1 + count))
        |> Map.update(:total, count, &(&1 + count))
      end)

    %{state | new_records: summaries}
  end
end
