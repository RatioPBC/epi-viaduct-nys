defmodule NYSETL.Engines.E2.TestResultProducerTest do
  use NYSETL.DataCase, async: false

  alias Broadway.Message
  alias NYSETL.ECLRS
  alias NYSETL.Engines.E2.TestResultProducer

  defmodule Forwarder do
    use Broadway

    def handle_message(_, message, %{test_pid: test_pid}) do
      send(test_pid, {:message_handled, message.data.tid})
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
          TestResultProducer,
          event_filters: ["processed", "parsed"], idle_timeout_ms: 500
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
    {:ok, _county} = ECLRS.find_or_create_county(71)
    {:ok, _county} = ECLRS.find_or_create_county(72)
    :ok
  end

  describe "handle_demand" do
    test "sends one event per TestResult without matched Events" do
      {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()
      {:ok, _test_result} = Factory.test_result_attrs(county_id: 71, file_id: file.id, tid: "no-events") |> ECLRS.create_test_result()
      {:ok, pid} = start_broadway()

      assert_receive({:message_handled, "no-events"})
      refute_receive({:message_handled, "no-events"}, 100)

      stop_broadway(pid)
    end

    test "sends one event per TestResult if existing events do not match filter" do
      {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()
      {:ok, test_result} = Factory.test_result_attrs(county_id: 71, file_id: file.id, tid: "has-other-events") |> ECLRS.create_test_result()
      {:ok, _test_result_event} = test_result |> ECLRS.save_event("did-it")
      {:ok, pid} = start_broadway()

      assert_receive({:message_handled, "has-other-events"})

      stop_broadway(pid)
    end

    test "does not send TestResults when the have associated Event records" do
      {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()

      {:ok, test_result} = Factory.test_result_attrs(county_id: 71, file_id: file.id, tid: "with-processed-event") |> ECLRS.create_test_result()

      {:ok, _test_result_event} = test_result |> ECLRS.save_event("processed")
      {:ok, test_result} = Factory.test_result_attrs(county_id: 71, file_id: file.id, tid: "with-parsed-event") |> ECLRS.create_test_result()
      {:ok, _test_result_event} = test_result |> ECLRS.save_event("other-event")
      {:ok, _test_result_event} = test_result |> ECLRS.save_event("parsed")
      {:ok, pid} = start_broadway()

      refute_receive({:message_handled, "with-processed-event"}, 100)
      refute_receive({:message_handled, "with-parsed-event"}, 100)

      stop_broadway(pid)
    end

    test "keeps trying to pull test results, even after test results are drained" do
      {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()
      {:ok, _test_result} = Factory.test_result_attrs(county_id: 71, file_id: file.id, tid: "no-event") |> ECLRS.create_test_result()
      {:ok, pid} = start_broadway()

      assert_receive({:message_handled, "no-event"})
      refute_receive({:message_handled, "new-event"}, 100)

      {:ok, _test_result} = Factory.test_result_attrs(county_id: 71, file_id: file.id, tid: "new-event") |> ECLRS.create_test_result()
      refute_receive({:message_handled, "no-event"})
      assert_receive({:message_handled, "new-event"}, 2000)

      stop_broadway(pid)
    end
  end
end
