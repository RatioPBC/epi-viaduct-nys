defmodule NYSETL.Engines.E2.Broadway do
  @moduledoc """
  This pipeline finds ECLRS.TestResult records which have not previously been
  processed, and feeds them into a Processor module which may do the following:

  * Do nothing
    * The lab result date is earlier than the configured threshold `:eclrs_ignore_before_timestamp`
    * Resolving conflicts between extant IndexCase and LabResult records results in no changes
  * Create new Person, IndexCase, and LabResult records
  * Create new IndexCase and LabResult records belonging to an existing Person
  * Create a new and LabResult records belonging to an existing IndexCase
  * Update existing IndexCase and/or LabResult records
  """
  use Broadway

  alias Broadway.Message
  alias NYSETL.ECLRS
  alias NYSETL.Engines.E2
  require Logger

  @behaviour Broadway.Acknowledger

  def start_link(_opts) do
    Logger.info("[#{__MODULE__}] starting")

    Broadway.start_link(__MODULE__,
      name: :"broadway.lab_results",
      producer: [
        module: {
          E2.TestResultProducer,
          event_filters: ["processed", "processing_failed"]
        },
        concurrency: 1,
        transformer: {__MODULE__, :transform, []}
      ],
      processors: [
        default: [concurrency: concurrency()]
      ]
    )
  end

  def transform(data, _) do
    %Message{
      data: data,
      acknowledger: {E2.Broadway, :ack_id, :ack_data}
    }
  end

  @impl true
  def handle_message(_, %Message{data: data} = message, _) do
    :ok = E2.Processor.process(data)

    message
  end

  @impl true
  @doc """
  For an `NYSETL.ECLRS.TestResult` record that has passed through the
  `E2.Broadway` pipeline, attach an associated
  `NYSETL.Event` record with one of the following values:

  * `processed`
  * `processing_failed`
  """
  def ack(_ref, successful, failed) do
    failed
    |> Enum.map(& &1.data)
    |> Enum.each(fn test_result ->
      ECLRS.save_event(test_result, "processing_failed")
      :telemetry.execute([:transformer, :lab_result, :processing_failed], %{count: 1})
    end)

    successful
    |> Enum.map(& &1.data)
    |> Enum.each(fn test_result ->
      ECLRS.save_event(test_result, "processed")
      :telemetry.execute([:transformer, :lab_result, :processed], %{count: 1})
    end)
  end

  defp concurrency(), do: Kernel.trunc(System.schedulers_online() / 2) |> Kernel.max(1)
end
