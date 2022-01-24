defmodule NYSETL.Engines.E3.IndexCaseProducerTest do
  use NYSETL.DataCase, async: false

  alias Broadway.Message
  alias NYSETL.Commcare
  alias NYSETL.ECLRS
  alias NYSETL.Engines.E3.IndexCaseProducer

  defmodule Forwarder do
    use Broadway

    def handle_message(_, message, %{test_pid: test_pid}) do
      send(test_pid, {:message_handled, tid: message.data.tid})
      message
    end

    def handle_batch(_, messages, _, _) do
      messages
    end
  end

  defp new_unique_name() do
    :"Broadway#{System.unique_integer([:positive, :monotonic])}"
  end

  defp start_broadway() do
    Broadway.start_link(Forwarder,
      name: new_unique_name(),
      context: %{test_pid: self()},
      producer: [
        module: {
          IndexCaseProducer,
          find_with_events_matching: ~w{
            index_case_created
            index_case_updated
            lab_result_created
            lab_result_updated
          }, reject_with_events_matching: ["send_to_commcare_enqueued"], idle_timeout_ms: 500
        },
        concurrency: 1,
        transformer: {__MODULE__, :transform, []}
      ],
      processors: [
        default: [concurrency: 5]
      ]
    )
  end

  def transform(data, _), do: %Message{data: data, acknowledger: {__MODULE__, :ack_id, :ack_data}}
  def ack(_, _, _), do: :ok

  defp stop_broadway(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :normal)

    receive do
      {:DOWN, ^ref, _, _, _} -> :ok
    end
  end

  setup do
    {:ok, county} = ECLRS.find_or_create_county(71)
    person = %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.Person.changeset() |> Repo.insert!()
    [county: county, person: person]
  end

  describe "handle_demand" do
    test "does not product an IndexCase without events", context do
      {:ok, _index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "no-events"} |> Commcare.create_index_case()

      {:ok, pid} = start_broadway()

      refute_receive({:message_handled, tid: "no-events"}, 100)

      stop_broadway(pid)
    end

    test "produces an IndexCase with events that do match find_with_events_matching", context do
      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "created"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("index_case_created")
      index_case |> Commcare.save_event("lab_result_created")

      {:ok, pid} = start_broadway()

      assert_receive({:message_handled, tid: "created"})
      refute_receive({:message_handled, tid: "created"}, 100)

      stop_broadway(pid)
    end

    test "does not produce an IndexCase with a later event matching reject_with_events_matching", context do
      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "already-enqueued"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("index_case_created")
      index_case |> Commcare.save_event("lab_result_created")
      index_case |> Commcare.save_event("send_to_commcare_enqueued")

      {:ok, pid} = start_broadway()

      refute_receive({:message_handled, tid: "already-enqueued"})

      stop_broadway(pid)
    end

    test "produces index cases with events more recent than those filtered by reject_with_events_matching", context do
      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "needs-resync"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("index_case_created")
      index_case |> Commcare.save_event("send_to_commcare_enqueued")
      index_case |> Commcare.save_event("index_case_updated")

      {:ok, pid} = start_broadway()

      assert_receive({:message_handled, tid: "needs-resync"})

      stop_broadway(pid)
    end

    test "keeps trying to pull index cases, even after test results are drained", context do
      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "first-event"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("index_case_created")

      {:ok, pid} = start_broadway()

      assert_receive({:message_handled, tid: "first-event"})
      refute_receive({:message_handled, tid: "first-event"}, 100)

      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "second-event"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("index_case_created")

      refute_receive({:message_handled, tid: "first-event"})
      assert_receive({:message_handled, tid: "second-event"}, 2000)

      stop_broadway(pid)
    end
  end

  describe "unprocessed_index_cases" do
    test "finds records with an event in the find list", context do
      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "ic-created"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("index_case_created")
      index_case |> Commcare.save_event("lab_result_untouched")

      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "ic-updated"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("index_case_updated")
      index_case |> Commcare.save_event("lab_result_untouched")

      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "lr-created"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("index_case_untouched")
      index_case |> Commcare.save_event("lab_result_created")

      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "lr-updated"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("index_case_untouched")
      index_case |> Commcare.save_event("lab_result_updated")

      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "untouched"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("retrieved_from_commcare")
      index_case |> Commcare.save_event("index_case_untouched")
      index_case |> Commcare.save_event("lab_result_untouched")

      IndexCaseProducer.unprocessed_index_cases(10, ~w{index_case_created index_case_updated lab_result_created lab_result_updated}, [])
      |> Repo.all()
      |> Euclid.Enum.tids()
      |> assert_eq(~w{ic-created ic-updated lr-created lr-updated})
    end

    test "rejects records where a more recent event matches the reject list", context do
      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "ic-created"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("index_case_created")
      index_case |> Commcare.save_event("send_to_commcare_enqueued")

      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "ic-updated"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("index_case_updated")
      index_case |> Commcare.save_event("send_to_commcare_enqueued")
      index_case |> Commcare.save_event("send_to_commcare_succeeded")

      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "lr-created"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("lab_result_created")
      index_case |> Commcare.save_event("send_to_commcare_failed")

      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "lr-updated"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("lab_result_updated")
      index_case |> Commcare.save_event("lab_result_untouched")

      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "untouched"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("retrieved_from_commcare")
      index_case |> Commcare.save_event("index_case_untouched")
      index_case |> Commcare.save_event("lab_result_untouched")

      IndexCaseProducer.unprocessed_index_cases(10, ~w{
        index_case_created
        index_case_updated
        lab_result_created
        lab_result_updated
      }, ~w{
        send_to_commcare_enqueued
        send_to_commcare_failed
        send_to_commcare_succeeded
      })
      |> Repo.all()
      |> Euclid.Enum.tids()
      |> assert_eq(~w{lr-updated})
    end

    test "finds records with events in the reject list, if more recent events exist from the find list", context do
      {:ok, index_case} = %{data: %{}, person_id: context.person.id, county_id: 71, tid: "updated"} |> Commcare.create_index_case()
      index_case |> Commcare.save_event("index_case_created")
      index_case |> Commcare.save_event("send_to_commcare_enqueued")
      index_case |> Commcare.save_event("index_case_updated")
      index_case |> Commcare.save_event("lab_result_untouched")

      IndexCaseProducer.unprocessed_index_cases(10, ~w{
        index_case_created
        index_case_updated
        lab_result_created
        lab_result_updated
      }, ~w{
        send_to_commcare_enqueued
        send_to_commcare_failed
        send_to_commcare_succeeded
      })
      |> Repo.all()
      |> Euclid.Enum.tids()
      |> assert_eq(~w{updated})
    end
  end
end
