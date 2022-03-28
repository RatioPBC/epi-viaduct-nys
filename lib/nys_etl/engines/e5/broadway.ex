defmodule NYSETL.Engines.E5.Broadway do
  @moduledoc """
  Fetches newly updated patient_cases from all counties in CommCare,
  and updates or creates IndexCases as needed.
  """

  use Broadway

  require Logger

  alias Broadway.Message
  alias NYSETL.Commcare.CaseImporter

  def start_link(county_list: county_list),
    do: start_link(county_list: county_list, start_date: two_days_ago())

  def start_link(county_list: county_list, start_date: start_date) do
    Logger.info("[#{__MODULE__}] starting")

    producer_module = Application.fetch_env!(:nys_etl, :e5_producer_module)

    Broadway.start_link(__MODULE__,
      name: :"broadway.engines.e5",
      producer: [
        module: {
          producer_module,
          county_list: county_list, idle_timeout_ms: 300_000, start_date: start_date
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
      acknowledger: {__MODULE__, :ack_id, :ack_data}
    }
  end

  def handle_message(_, %Message{} = message, _) do
    [case: case, county: county] = message.data
    Logger.info("[#{__MODULE__}] starting processing of index_case case_id=#{case["case_id"]} county=#{county.domain}")

    message.data
    |> CaseImporter.import_case()

    message
  end

  def handle_failed(messages, _context) do
    messages
    |> Enum.each(fn %Broadway.Message{data: [case: case, county: county]} ->
      Logger.info("[#{__MODULE__}] failed processing of index_case case_id=#{case["case_id"]} county=#{county.domain}")
    end)

    messages
  end

  def ack(:ack_id, _successful, _failed) do
    :ok
  end

  defp two_days_ago(), do: Date.utc_today() |> Date.add(-2)
  defp concurrency(), do: Kernel.trunc(System.schedulers_online() * 2)
end
