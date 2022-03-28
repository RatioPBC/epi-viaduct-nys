defmodule NYSETL.Engines.E5.ProducerTest do
  use NYSETL.DataCase, async: false

  import ExUnit.CaptureLog
  import Mox
  setup :verify_on_exit!
  setup :set_mox_from_context

  alias NYSETL.ECLRS
  alias NYSETL.Engines.E5
  alias NYSETL.Test

  setup do
    {:ok, _} = start_supervised(E5.PollingConfig)
    {:ok, true} = FunWithFlags.enable(:commcare_case_forwarder)
    :ok
  end

  defmodule Forwarder do
    use Broadway
    alias Broadway.Message

    def handle_message(_, %{data: data} = msg, %{test_pid: test_pid}) do
      [case: case, county: county] = data
      send(test_pid, {:message_handled, case["case_id"], county})
      msg
    end

    def handle_batch(_, messages, _, _) do
      messages
    end

    def transform(data, _), do: %Message{data: data, acknowledger: {__MODULE__, :ack_id, :ack_data}}
    def ack(_, _, _), do: :ok
  end

  defp new_unique_name() do
    :"Broadway#{System.unique_integer([:positive, :monotonic])}"
  end

  @county_list [
    %{domain: "uk-midsomer-cdcms"},
    %{domain: "sw-yggdrasil-cdcms"}
  ]
  defp start_broadway() do
    Broadway.start_link(Forwarder,
      name: new_unique_name(),
      context: %{test_pid: self()},
      producer: [
        module: {
          E5.Producer,
          county_list: @county_list, idle_timeout_ms: 500, start_date: ~D[2020-06-30]
        },
        concurrency: 1,
        transformer: {Forwarder, :transform, []}
      ],
      processors: [
        default: [concurrency: 10]
      ]
    )
  end

  defp stop_broadway(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :normal)

    receive do
      {:DOWN, ^ref, _, _, _} -> :ok
    end
  end

  setup do
    {:ok, _midsomer} = ECLRS.find_or_create_county(1111)
    {:ok, _ygg} = ECLRS.find_or_create_county(9999)
    {:ok, _statewide} = ECLRS.find_or_create_county(1234)

    :ok
  end

  describe "handle_demand success cases" do
    setup do
      NYSETL.HTTPoisonMock
      |> stub(:get, fn
        "http://commcare.test.host/a/uk-midsomer-cdcms/api/v0.5/case/?" <>
          "server_date_modified_start=2020-06-30" <>
          "&child_cases__full=true&type=patient&limit=100&offset=" <>
          offset = url,
        _headers,
        _opts ->
          body = Test.Fixtures.cases_response("uk-midsomer-cdcms", "patient", offset)
          {:ok, %{body: body, status_code: 200, request_url: url}}

        "http://commcare.test.host/a/uk-midsomer-cdcms/api/v0.5/case/?" <>
          "server_date_modified_start=" <>
          <<date::binary-size(10)>> <>
          "&child_cases__full=true&type=patient&limit=100&offset=" <>
          offset = url,
        _headers,
        _opts ->
          date |> assert_eq(Date.utc_today() |> Date.to_string())
          body = Test.Fixtures.cases_response("uk-midsomer-cdcms_modified-today", "patient", offset)
          {:ok, %{body: body, status_code: 200, request_url: url}}

        "http://commcare.test.host/a/sw-yggdrasil-cdcms/api/v0.5/case/?" <>
          "server_date_modified_start=2020-06-30" <>
          "&child_cases__full=true&type=patient&limit=100&offset=" <>
          offset = url,
        _headers,
        _opts ->
          body = Test.Fixtures.cases_response("sw-yggdrasil-cdcms", "patient", offset)
          {:ok, %{body: body, status_code: 200, request_url: url}}

        "http://commcare.test.host/a/sw-yggdrasil-cdcms/api/v0.5/case/?" <>
          "server_date_modified_start=" <>
          <<date::binary-size(10)>> <>
          "&child_cases__full=true&type=patient&limit=100&offset=" <>
          offset = url,
        _headers,
        _opts ->
          date |> assert_eq(Date.utc_today() |> Date.to_string())
          body = Test.Fixtures.cases_response("sw-yggdrasil-cdcms_modified-today", "patient", offset)
          {:ok, %{body: body, status_code: 200, request_url: url}}
      end)

      :ok
    end

    test "sends one event per case per county in CommCare" do
      {:ok, pid} = start_broadway()

      assert_receive({:message_handled, "commcare_case_id_ms_1", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ms_2", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ms_3", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ms_4", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ms_5", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ms_6", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ms_7", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ms_8", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ms_9", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ms_10", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ms_11", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ms_12", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ms_13", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ms_14", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ms_15", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ygg_1", %{domain: "sw-yggdrasil-cdcms"}})

      refute_receive({:message_handled, "commcare_case_id_ms_1", _}, 50)
      refute_receive({:message_handled, "commcare_case_id_ms_2", _}, 50)
      refute_receive({:message_handled, "commcare_case_id_ygg_1", _}, 50)

      refute_receive({:message_handled, "commcare_case_id_ms_new", _}, 50)
      refute_receive({:message_handled, "commcare_case_id_ygg_new", _}, 50)

      stop_broadway(pid)
    end

    test "dynamically includes and excludes counties" do
      assert :ok = E5.PollingConfig.disable("uk-midsomer-cdcms")

      {:ok, pid} = start_broadway()

      refute_receive({:message_handled, "commcare_case_id_ms_1", _}, 50)
      assert_receive({:message_handled, "commcare_case_id_ygg_1", %{domain: "sw-yggdrasil-cdcms"}})

      assert :ok = E5.PollingConfig.enable("uk-midsomer-cdcms")
      assert_receive({:message_handled, "commcare_case_id_ms_new", %{domain: "uk-midsomer-cdcms"}}, 2000)

      stop_broadway(pid)
    end

    test "wakes after an idle timeout, with start date set to today" do
      {:ok, pid} = start_broadway()

      assert_receive({:message_handled, "commcare_case_id_ms_1", %{domain: "uk-midsomer-cdcms"}})
      assert_receive({:message_handled, "commcare_case_id_ygg_1", %{domain: "sw-yggdrasil-cdcms"}})
      refute_receive({:message_handled, "commcare_case_id_ms_1", _}, 100)
      refute_receive({:message_handled, "commcare_case_id_ygg_1", _}, 100)

      assert_receive({:message_handled, "commcare_case_id_ms_new", %{domain: "uk-midsomer-cdcms"}}, 2000)
      assert_receive({:message_handled, "commcare_case_id_ygg_new", %{domain: "sw-yggdrasil-cdcms"}})

      stop_broadway(pid)
    end
  end

  describe "handle_demand error cases" do
    setup do
      test_pid = self()

      NYSETL.HTTPoisonMock
      |> stub(:get, fn
        "http://commcare.test.host/a/uk-midsomer-cdcms/api/v0.5/case/?" <>
          "server_date_modified_start=" <> _params = url,
        _headers,
        _opts ->
          # All requests to first county
          send(test_pid, {:http_request, url})
          {:ok, %{body: "", status_code: 403, request_url: url}}

        "http://commcare.test.host/a/sw-yggdrasil-cdcms/api/v0.5/case/?" <>
          "server_date_modified_start=2020-06-30" <>
          "&child_cases__full=true&type=patient&limit=100&offset=" <>
          offset = url,
        _headers,
        _opts ->
          # First request to second county
          send(test_pid, {:http_request, url})
          body = Test.Fixtures.cases_response("sw-yggdrasil-cdcms", "patient", offset)
          {:ok, %{body: body, status_code: 200, request_url: url}}

        "http://commcare.test.host/a/uk-midsomer-cdcms/api/v0.5/case/?" <>
          "server_date_modified_start=" <>
          <<_date::binary-size(10)>> <>
          "&child_cases__full=true&type=patient&limit=100&offset=" <>
          _offset = url,
        _headers,
        _opts ->
          # final request to second county
          send(test_pid, {:http_request, url})
          {:ok, %{body: "", status_code: 500, request_url: url}}

        "http://commcare.test.host/a/sw-yggdrasil-cdcms/api/v0.5/case/?" <>
          "server_date_modified_start=" <>
          <<_date::binary-size(10)>> <>
          "&child_cases__full=true&type=patient&limit=100&offset=" <>
          _offset = url,
        _headers,
        _opts ->
          # final request to second county
          send(test_pid, {:http_request, url})
          {:ok, %{body: "", status_code: 500, request_url: url}}
      end)

      :ok
    end

    def assert_url(url, domain: domain, date: date, offset: offset) do
      url
      |> assert_eq(
        "http://commcare.test.host" <>
          "/a/" <>
          to_string(domain) <>
          "/api/v0.5/case/?server_date_modified_start=" <>
          to_string(date) <>
          "&child_cases__full=true&type=patient&limit=100&offset=" <>
          to_string(offset)
      )
    end

    test "moves on to next county when an error is seen" do
      output =
        capture_log(fn ->
          {:ok, pid} = start_broadway()

          today_as_string = Date.utc_today() |> Date.to_string()

          step "request to first domain results in 403 response" do
            assert_receive({:http_request, url})
            assert_url(url, domain: "uk-midsomer-cdcms", date: "2020-06-30", offset: 0)
            refute_receive({:message_handled, "commcare_case_id_ms_1", _}, 100)
          end

          step "producer moves on to second domain, with a success response" do
            assert_receive({:http_request, url})
            assert_url(url, domain: "sw-yggdrasil-cdcms", date: "2020-06-30", offset: 0)
            assert_receive({:message_handled, "commcare_case_id_ygg_1", %{domain: "sw-yggdrasil-cdcms"}})
          end

          step "after sleeping a while, producer wakes up, receives 500 response" do
            assert_receive({:http_request, url}, 2000)
            assert_url(url, domain: "sw-yggdrasil-cdcms", date: today_as_string, offset: 0)
            refute_receive({:message_handled, "commcare_case_id_ms_new", _}, 100)
          end

          step "producer moves on to the next county" do
            assert_receive({:http_request, url}, 2000)
            assert_url(url, domain: "uk-midsomer-cdcms", date: today_as_string, offset: 0)
            refute_receive({:message_handled, "commcare_case_id_ms_new", _}, 100)
          end

          stop_broadway(pid)
        end)

      assert output =~ "error fetching cases from CommCare"
    end
  end
end
