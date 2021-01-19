defmodule NYSETL.EndToEndTest do
  use NYSETL.DataCase, async: false

  import Mox
  alias NYSETL.Test.Factory
  alias NYSETL.Test.Fixtures
  alias NYSETL.Test.Xml
  require Ecto.Query
  setup :verify_on_exit!
  setup :set_mox_from_context

  def clear_cache(_context) do
    NYSETL.Engines.E1.Cache.clear()

    on_exit(fn ->
      NYSETL.Engines.E1.Cache.clear()
    end)
  end

  defp handle_oban_telemetry([:oban, :job, event], _, meta, _, test_pid) do
    send(test_pid, {:oban, event, meta})
  end

  def attach_oban_telemetry(_context) do
    test_pid = self()
    test_pid_string = self() |> :erlang.pid_to_list() |> to_string()

    :ok =
      :telemetry.attach_many(
        "test-oban-errors-#{test_pid_string}",
        [[:oban, :job, :start], [:oban, :job, :stop], [:oban, :job, :exception]],
        &handle_oban_telemetry(&1, &2, &3, &4, test_pid),
        %{}
      )

    on_exit(fn ->
      :telemetry.detach("test-oban-errors-#{test_pid_string}")
    end)

    :ok
  end

  def start_pipelines(_context) do
    {:ok, _pid} = start_supervised(NYSETL.ViaductSupervisor)
    :ok
  end

  def stop_pipelines() do
    stop_supervised(NYSETL.ViaductSupervisor)
  end

  defmodule HTTPoisonMockServer do
    use GenServer
    use NYSETL.Test.HTTPoisonMockBase

    @behaviour HTTPoison.Base

    defstruct [
      :test_pid,
      registered_gets: []
    ]

    # GenServer init

    def start_link(args) do
      GenServer.start_link(__MODULE__, args, name: __MODULE__)
    end

    ## public api

    def register_get(url, response), do: GenServer.call(__MODULE__, {:register_get, url, response})

    @impl true
    def get(url, body, headers), do: GenServer.call(__MODULE__, {:get, url, body, headers})

    @impl true
    def post(url, body, headers), do: GenServer.call(__MODULE__, {:post, url, body, headers})

    ## callbacks

    @impl true
    def init(%{test_pid: test_pid}) do
      {:ok, %__MODULE__{test_pid: test_pid}}
    end

    @impl true
    def handle_call({:register_get, url, response}, _from, state) do
      {:reply, :ok, %{state | registered_gets: [{url, response} | state.registered_gets]}}
    end

    @impl true
    def handle_call({:get, url, _body, _headers}, _from, %{registered_gets: requests} = state) do
      matched_request_index =
        requests
        |> Enum.find_index(fn {request_url, _response} ->
          url =~ request_url
        end)

      cond do
        not is_nil(matched_request_index) ->
          send(state.test_pid, :found_registered_request)
          {{_url, response}, registered_gets} = List.pop_at(requests, matched_request_index)
          {:reply, {:ok, response}, %{state | registered_gets: registered_gets}}

        url =~ "server_date_modified_start" ->
          response = """
          {
            "objects": [],
            "meta": {}
          }
          """

          {:reply, {:ok, %{body: response, status_code: 200, request_url: ""}}, state}

        url =~ "http://commcare.test.host/a/sw-yggdrasil-cdcms/api/v0.5/case/" ->
          {:reply, {:ok, %{body: "", status_code: 404, request_url: ""}}, state}

        url =~ "http://commcare.test.host/a/uk-midsomer-cdcms/api/v0.5/case/" ->
          {:reply, {:ok, %{body: "", status_code: 404, request_url: ""}}, state}

        url =~ "http://commcare.test.host/a/ny-test-cdcms/api/v0.5/fixture/?fixture_type=county_list" ->
          {:reply, {:ok, %{body: Fixtures.county_list_response(), status_code: 200}}, state}
      end
    end

    @impl true
    def handle_call({:post, url, body, _headers}, _from, state) do
      send(state.test_pid, {:http, :post, url, body})
      {:reply, {:ok, %HTTPoison.Response{status_code: 201, body: "submit_success you did it!"}}, state}
    end
  end

  def mock_commcare_get_api(_context) do
    _pid = start_supervised!({HTTPoisonMockServer, %{test_pid: self()}})
    NYSETL.HTTPoisonMock |> stub_with(HTTPoisonMockServer)
    :ok
  end

  def mock_sqs(_) do
    Application.put_env(:nys_etl, :sqs_arn, "https://doesnt-matter")

    Mox.stub(NYSETL.ExAwsMock, :request!, fn %ExAws.Operation.Query{action: :receive_message} -> %{body: %{messages: []}} end)

    :ok
  end

  def assert_people_created(people_attrs) do
    assert NYSETL.Commcare.Person
           |> Ecto.Query.order_by(asc: :name_last)
           |> Repo.all()
           |> Extra.Enum.pluck([:dob, :name_last, :name_first, :patient_keys]) == people_attrs
  end

  def index_cases_created() do
    NYSETL.Commcare.IndexCase
    |> Ecto.Query.order_by(asc: :id)
    |> Repo.all()
  end

  setup ~w{
    clear_cache
    mock_commcare_get_api
    mock_sqs
    start_pipelines
    attach_oban_telemetry
  }a

  @path "test/fixtures/eclrs/new_records.txt"

  test "reads rows from a file, processes them, and eventually posts records to CommCare", _context do
    NYSETL.Engines.E1.ECLRSFileExtractor.extract!(@path)

    assert_receive({:oban, :stop, %{worker: "NYSETL.Engines.E4.CommcareCaseLoader"}}, 15_000)
    assert_receive({:oban, :stop, %{worker: "NYSETL.Engines.E4.CommcareCaseLoader"}}, 1_000)

    assert_received({:http, :post, "http://commcare.test.host/a/sw-yggdrasil-cdcms/receiver/", _})
    assert_received({:http, :post, "http://commcare.test.host/a/uk-midsomer-cdcms/receiver/", _})

    refute_received({:oban, :exception, _}, 100)

    stop_pipelines()

    assert_people_created([
      %{dob: ~D[1947-03-01], name_first: "FIRSTNAME", name_last: "LASTNAME", patient_keys: ["15200000000000"]},
      %{dob: ~D[1970-01-01], name_first: "AGENT", name_last: "SMITH", patient_keys: ["15200000000001"]}
    ])
  end

  test "Viaduct uses the owner_id associated with the ECLRS Fips, rather than the owner_id of the index_case in the DB", _context do
    county_id = Fixtures.test_county_1_fips() |> String.to_integer()
    original_owner_id = Fixtures.test_county_1_location_id()
    {:ok, _county} = NYSETL.ECLRS.find_or_create_county(county_id)
    {:ok, file} = Factory.file_attrs() |> NYSETL.ECLRS.create_file()

    step "process an initial ECLRS test result" do
      {:ok, _first_test_result} =
        Fixtures.test_result(
          county_id: county_id,
          file_id: file.id,
          request_accession_number: "ABC123"
        )
        |> NYSETL.ECLRS.create_test_result()

      assert_receive({:oban, :stop, %{worker: "NYSETL.Engines.E4.CommcareCaseLoader"}}, 15_000)

      expected_post_url = "http://commcare.test.host/a/#{Fixtures.test_county_1_domain()}/receiver/"
      assert_received({:http, :post, ^expected_post_url, _})

      assert_people_created([
        %{dob: ~D[1960-01-01], name_first: "TEST", name_last: "USER", patient_keys: ["12345"]}
      ])

      [index_case] = index_cases_created()
      assert %{county_id: ^county_id, data: %{"owner_id" => ^original_owner_id}} = index_case
    end

    index_case =
      step "CommCare updates the owner id" do
        new_data = index_case.data |> Map.put("owner_id", "other_owner_id")
        NYSETL.Commcare.update_index_case_from_commcare_data(index_case, new_data)

        [index_case] = index_cases_created()
        assert %{county_id: ^county_id, data: %{"owner_id" => "other_owner_id"}} = index_case
        index_case
      end

    step "receive a new ECLRS test result for the same index case" do
      get_url = "http://commcare.test.host/a/#{Fixtures.test_county_1_domain()}/api/v0.5/case/#{index_case.case_id}/"
      response = Fixtures.commcare_case_response(index_case.case_id, index_case.data) |> Jason.encode!()
      HTTPoisonMockServer.register_get(get_url, %{body: response, status_code: 200, request_url: ""})

      {:ok, _second_test_result} =
        Fixtures.test_result(
          county_id: county_id,
          file_id: file.id,
          request_accession_number: "ZED0987"
        )
        |> NYSETL.ECLRS.create_test_result()

      assert_receive({:oban, :stop, %{worker: "NYSETL.Engines.E4.CommcareCaseLoader"}}, 15_000)
      expected_post_url = "http://commcare.test.host/a/#{Fixtures.test_county_1_domain()}/receiver/"
      assert_received(:found_registered_request)
      assert_received({:http, :post, ^expected_post_url, posted_body})

      doc = Floki.parse_document!(posted_body)

      assert Xml.text(doc, "case:nth-of-type(1) create owner_id") == original_owner_id
      assert Xml.text(doc, "case:nth-of-type(1) update owner_id") == original_owner_id
    end

    # 3 configure a mock to observe the next index_case update that we post to commcare
    # 4 process a new test case for the same index case in step 1, reflecting owner_id=A
    # 5 use the mock to verify that the update to commcare includes owner_id=A
    stop_pipelines()
  end
end
