defmodule NYSETL.Engines.E3.Broadway do
  use Broadway

  alias Broadway.Message
  alias NYSETL.Commcare
  alias NYSETL.Engines.E3
  alias NYSETL.Engines.E4
  require Logger

  @events_to_find ~w{
    index_case_created
    index_case_updated
    lab_result_created
    lab_result_updated
  }

  # Here we include send_to_commcare_failed and send_to_commcare_succeeded, rather than merely
  # including send_to_commcare_enqueued, because there are cases such as transfers in which an
  # index case might have a send_to_commcare_succeeded event without previously having
  # a send_to_commcare_enqueued event.
  #
  # The send_to_commcare_enqueued event appears on the source case, and the send_to_commcare_succeeded
  # appears on the destination case.
  @events_to_reject ~w{
    send_to_commcare_enqueued
    send_to_commcare_failed
    send_to_commcare_succeeded
  }

  def start_link(_) do
    Logger.info("[#{__MODULE__}] starting")

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {
          E3.IndexCaseProducer,
          find_with_events_matching: @events_to_find, reject_with_events_matching: @events_to_reject
        },
        concurrency: 1,
        transformer: {__MODULE__, :transform, []}
      ],
      processors: [
        default: [concurrency: 1]
      ]
    )
  end

  def ack(:ack_id, _successful, _failed) do
    :ok
  end

  def transform(data, _) do
    %Message{
      data: data,
      acknowledger: {__MODULE__, :ack_id, :ack_data}
    }
  end

  def handle_message(_, %Message{data: data} = message, _) do
    %{"case_id" => data.case_id, "county_id" => data.county_id}
    |> E4.CommcareCaseLoader.new()
    |> Oban.insert()

    Commcare.save_event(data, "send_to_commcare_enqueued")
    :telemetry.execute([:loader, :commcare, :enqueued], %{count: 1})

    message
  end
end
