defmodule NYSETL.Engines.E4.CaseTransferChainTest do
  use NYSETL.SimpleCase, async: true
  use NYSETL.DataCase, async: true

  import ExUnit.CaptureLog
  import Mox
  setup :verify_on_exit!

  alias Euclid.Term
  alias NYSETL.Commcare
  alias NYSETL.ECLRS
  alias NYSETL.Engines.E4.{CaseIdentifier, CaseTransferChain, PatientCaseData}

  describe "follow_transfers" do
    setup do
      %{
        transferred_case_1: %{
          case_id: "transferred-case-1",
          domain: Test.Fixtures.test_county_1_domain(),
          transfer_destination_county_id: Test.Fixtures.test_county_2_fips()
        },
        transferred_case_2: %{
          case_id: "transferred-case-2",
          domain: Test.Fixtures.test_county_2_domain(),
          transfer_destination_county_id: Test.Fixtures.test_county_3_fips(),
          transfer_source_case_id: "transferred-case-1"
        },
        transfer_destination_case: %{
          case_id: "transfer-destination-case",
          domain: Test.Fixtures.test_county_3_domain(),
          transfer_destination_county_id: Test.Fixtures.test_county_3_fips(),
          transfer_source_case_id: "transferred-case-2"
        },
        non_transferred_case: %{
          case_id: "non-transferred-case",
          domain: Test.Fixtures.test_county_3_domain()
        },
        transferred_to_bad_county: %{
          case_id: "transferred-to-bad-county",
          domain: Test.Fixtures.test_county_3_domain(),
          transfer_destination_county_id: "123456789",
          transfer_source_case_id: "transferred-case-2"
        },
        non_existent_case: %{
          case_id: "non-existent-case",
          domain: ""
        },
        transferred_case_causes_cycle: %{
          case_id: "transferred-case-causes-cycle",
          domain: Test.Fixtures.test_county_2_domain(),
          transfer_destination_county_id: Test.Fixtures.test_county_1_fips(),
          transfer_source_case_id: "transferred-case-1"
        }
      }
    end

    test "returns the requested case when its data do not indicate a transfer", context do
      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        mock_case_requests(url, [context.non_transferred_case])
      end)

      CaseIdentifier.new(case_id: context.non_transferred_case.case_id, county_domain: context.non_transferred_case.domain)
      |> CaseTransferChain.follow_transfers(%{})
      |> CaseTransferChain.describe()
      |> assert_eq(["non-transferred-case@uk-statewide-cdcms"])
    end

    test "returns requested case and transferred case when the requested case's data indicate a transfer", context do
      NYSETL.HTTPoisonMock
      |> stub(:get, fn url, _headers, _opts ->
        mock_case_requests(url, [context.transferred_case_1, context.transferred_case_2, context.transfer_destination_case])
      end)

      CaseIdentifier.new(case_id: "transferred-case-1", county_domain: context.transferred_case_1.domain)
      |> CaseTransferChain.follow_transfers(%{})
      |> CaseTransferChain.describe()
      |> assert_eq([
        "transfer-destination-case@uk-statewide-cdcms",
        "transferred-case-2@sw-yggdrasil-cdcms",
        "transferred-case-1@uk-midsomer-cdcms"
      ])
    end

    test "returns the accumulated chain with :not_found if the case can't be found in the target domain", context do
      NYSETL.HTTPoisonMock
      |> stub(:get, fn url, _headers, _opts ->
        mock_case_requests(url, [context.transferred_case_1, context.non_existent_case])
      end)

      CaseIdentifier.new(case_id: "transferred-case-1", county_domain: context.transferred_case_1.domain)
      |> CaseTransferChain.follow_transfers(%{})
      |> CaseTransferChain.describe()
      |> assert_eq([:not_found, "transferred-case-1@uk-midsomer-cdcms"])
    end

    test "returns the accumulated chain with an error indicating the transfer target county does not exist", context do
      NYSETL.HTTPoisonMock
      |> stub(:get, fn url, _headers, _opts ->
        mock_case_requests(url, [context.transferred_case_1, context.transferred_case_2, context.transferred_to_bad_county])
      end)

      CaseIdentifier.new(case_id: "transferred-case-1", county_domain: context.transferred_case_1.domain)
      |> CaseTransferChain.follow_transfers(%{})
      |> CaseTransferChain.describe()
      |> assert_eq([
        {:error, "no county found with FIPS code '123456789'"},
        "transferred-case-2@sw-yggdrasil-cdcms",
        "transferred-case-1@uk-midsomer-cdcms"
      ])
    end

    test "returns the accumulated chain with an error indicating that one of the requests failed" do
      result = %{
        "case_id" => "transferred-case-1",
        "properties" => %{"external_id" => "external-id", "transfer_destination_county_id" => Test.Fixtures.test_county_2_fips()}
      }

      NYSETL.HTTPoisonMock
      |> stub(:get, fn
        url, _headers, _opts ->
          cond do
            url =~ "/api/v0.5/case/transferred-case-1/" -> {:ok, %{status_code: 200, body: result |> Jason.encode!()}}
            url =~ "/api/v0.5/case/?external_id=external-id" -> {:something, %{status_code: 429}}
            true -> raise "unexpected URL"
          end
      end)

      assert capture_log(fn ->
               CaseIdentifier.new(case_id: "transferred-case-1", county_domain: Test.Fixtures.test_county_1_domain())
               |> CaseTransferChain.follow_transfers(%{attempt: 1})
               |> CaseTransferChain.describe()
               |> assert_eq([
                 {:error, :rate_limited},
                 "transferred-case-1@uk-midsomer-cdcms"
               ])
             end) =~ "rate_limited"
    end

    test "returns an error if the chain of transfers contains a cycle", context do
      NYSETL.HTTPoisonMock
      |> stub(:get, fn url, _headers, _opts ->
        mock_case_requests(url, [context.transferred_case_1, context.transferred_case_causes_cycle])
      end)

      assert capture_log(fn ->
               CaseIdentifier.new(case_id: "transferred-case-1", county_domain: context.transferred_case_1.domain)
               |> CaseTransferChain.follow_transfers(%{})
               |> CaseTransferChain.describe()
               |> assert_eq([:cycle_detected, "transferred-case-1@uk-midsomer-cdcms"])
             end) =~ "Case transfer cycle detected"
    end
  end

  describe "contains_county_domain?" do
    test "returns true iff any of the PatientCaseData elements has the given county domain" do
      chain = [
        PatientCaseData.new(%{}, "ny-county-1"),
        PatientCaseData.new(%{}),
        :something,
        PatientCaseData.new(%{}, "ny-county-2")
      ]

      assert chain |> CaseTransferChain.contains_county_domain?("ny-county-2")
      refute chain |> CaseTransferChain.contains_county_domain?("ny-county-5000")
    end
  end

  describe "describe" do
    test "returns a simplified version of the chain for testing/debugging purposes" do
      [%PatientCaseData{case_id: "case-id-123", county_domain: "ny-test-domain", external_id: "external-id-123"}, :not_found, {:x, :y, :z}]
      |> CaseTransferChain.describe()
      |> assert_eq(["case-id-123@ny-test-domain", :not_found, {:x, :y, :z}])
    end
  end

  describe "resolve without a county transfer" do
    test "if the chain contains a single PatientCaseData, it returns that" do
      initial_case = PatientCaseData.new(%{"case_id" => "initial"})

      assert [initial_case] |> CaseTransferChain.resolve() == {{:ok, initial_case}, :no_transfer}
    end

    test "if the chain contains a single error, it returns that, and :no_transfer" do
      assert [:not_found] |> CaseTransferChain.resolve() == {:not_found, :no_transfer}
      assert [{:error, "message"}] |> CaseTransferChain.resolve() == {{:error, "message"}, :no_transfer}
    end
  end

  describe "resolve with a county transfer" do
    test "returns first PatientCaseData of the chain, and :transfer, if the chain contains >1 elements, all of which are PatientCaseData" do
      initial_case = PatientCaseData.new(%{"case_id" => "initial"})
      intermediate_case = PatientCaseData.new(%{"case_id" => "intermediate"})
      final_case = PatientCaseData.new(%{"case_id" => "final"})

      assert [final_case, intermediate_case, initial_case] |> CaseTransferChain.resolve() == {{:ok, final_case}, :transfer}
    end

    test "if the chain includes something other than PatientCaseData, the first of those is returned, with :transfer" do
      case_data = PatientCaseData.new(%{"case_id" => "a"})

      assert [:not_found, case_data] |> CaseTransferChain.resolve() == {:not_found, :transfer}
      assert [{:error, "message"}, case_data] |> CaseTransferChain.resolve() == {{:error, "message"}, :transfer}
    end

    test "just in case there is more than one non-PatientCaseData, return the one that ocurred earliest, with :transfer" do
      case_data_a = PatientCaseData.new(%{"case_id" => "a"})
      case_data_b = PatientCaseData.new(%{"case_id" => "b"})

      assert [:last, case_data_b, :first, case_data_a] |> CaseTransferChain.resolve() == {:first, :transfer}
    end

    defp mock_case_requests(url, cases) do
      cases
      |> Enum.find_value(fn case ->
        result = %{
          "case_id" => case.case_id,
          "properties" => %{"external_id" => "external-id"}
        }

        result =
          if Term.presence(case[:transfer_destination_county_id]) do
            put_in(result, ["properties", "transfer_destination_county_id"], case[:transfer_destination_county_id])
          else
            result
          end

        result =
          if Term.presence(case[:transfer_source_case_id]) do
            put_in(result, ["properties", "transfer_source_case_id"], case[:transfer_source_case_id])
          else
            result
          end

        cond do
          url =~ "/a/bad-domain" -> {401, ~s|{"error": "Your current subscription does not have access to this feature"}|}
          url =~ "/a/#{case.domain}/api/v0.5/case/#{case.case_id}/" -> {200, result}
          url =~ "/a/#{case.domain}/api/v0.5/case/?external_id=external-id" -> {200, %{"objects" => [result]}}
          true -> nil
        end
      end)
      |> case do
        nil -> {:ok, %{status_code: 404, body: "case not found: #{url}"}}
        {status_code, body} -> {:ok, %{status_code: status_code, body: body |> Jason.encode!()}}
      end
    end
  end

  describe "fetch_case" do
    test "when there are no objects returned, it returns :no_cases_match" do
      NYSETL.HTTPoisonMock
      |> stub(:get, fn "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/?external_id=1234567" = url, _headers, _opts ->
        body = Test.Fixtures.case_external_id_response("empty_result", "1234567")
        {:ok, %{body: body, status_code: 200, request_url: url}}
      end)

      case_identifier =
        CaseIdentifier.new(
          transfer_source_case_id: "source-case-id",
          external_id: "1234567",
          county_domain: "nj-covid-camden"
        )

      assert CaseTransferChain.fetch_case(case_identifier) == {:no_case_matches, {"source-case-id", []}}
    end

    test "when there is one object returned, it returns that object" do
      NYSETL.HTTPoisonMock
      |> stub(:get, fn "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/?external_id=1234567" = url, _headers, _opts ->
        body = Test.Fixtures.case_external_id_response("nj-covid-camden", "1234567")
        {:ok, %{body: body, status_code: 200, request_url: url}}
      end)

      case_identifier =
        CaseIdentifier.new(
          transfer_source_case_id: "does-not-matter;should-be-ignored",
          external_id: "1234567",
          county_domain: "nj-covid-camden"
        )

      {:ok, the_case} = CaseTransferChain.fetch_case(case_identifier)
      assert %{"case_id" => "12345678-1234-1234-1234-123456789012"} = the_case
    end

    test "when there is more than one object returned, it returns the object associated with the right transfer source" do
      NYSETL.HTTPoisonMock
      |> stub(:get, fn "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/?external_id=1234567" = url, _headers, _opts ->
        body = Test.Fixtures.case_external_id_response("more_than_one_result", "1234567")
        {:ok, %{body: body, status_code: 200, request_url: url}}
      end)

      case_identifier =
        CaseIdentifier.new(
          transfer_source_case_id: "de28b564-f216-4a34-a1e3-73e9d9a4fb2f",
          external_id: "1234567",
          county_domain: "nj-covid-camden"
        )

      {:ok, the_case} = CaseTransferChain.fetch_case(case_identifier)
      assert %{"case_id" => "a93c2f8d43fe4ecd90345c8a7e0d2f4a"} = the_case
    end
  end

  describe "fetch_case when initial results are empty" do
    test "it looks in our DB for cases in the destination county that have a matching transfer_source_case_id" do
      destination_case_id = "12345678-1234-1234-1234-123456789012"

      NYSETL.HTTPoisonMock
      |> stub(:get, fn url, _headers, _opts ->
        cond do
          url == "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/?external_id=1234567" ->
            body = Test.Fixtures.case_external_id_response("empty_result", "1234567")
            {:ok, %{body: body, status_code: 200, request_url: url}}

          url == "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/12345678-1234-1234-1234-123456789012/?format=json&child_cases__full=true" ->
            body = Test.Fixtures.case_response("nj-covid-camden", "12345678-1234-1234-1234-123456789012")
            {:ok, %{body: body, status_code: 200, request_url: url}}
        end
      end)

      set_up_index_case(%{case_id: destination_case_id, data: %{transfer_source_case_id: "source-case-id"}})
      set_up_index_case(%{case_id: "source-case-id", data: %{external_id: "1234567"}})

      case_identifier =
        CaseIdentifier.new(
          transfer_source_case_id: "source-case-id",
          external_id: "1234567",
          county_domain: "nj-covid-camden"
        )

      {:ok, case} = CaseTransferChain.fetch_case(case_identifier)
      assert %{"case_id" => "12345678-1234-1234-1234-123456789012"} = case
    end

    test "when the destination case is a duplicate, it follows the duplicate chain" do
      terminal_case_id = "12345678-1234-1234-1234-123456789012"
      duplicate_1_case_id = "duplicate-1"
      duplicate_2_case_id = "duplicate-2"

      NYSETL.HTTPoisonMock
      |> stub(:get, fn url, _headers, _opts ->
        cond do
          url == "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/?external_id=1234567" ->
            body = Test.Fixtures.case_external_id_response("empty_result", "1234567")
            {:ok, %{body: body, status_code: 200, request_url: url}}

          url == "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/#{terminal_case_id}/?format=json&child_cases__full=true" ->
            body = Test.Fixtures.case_response("nj-covid-camden", terminal_case_id)
            {:ok, %{body: body, status_code: 200, request_url: url}}

          url == "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/#{duplicate_1_case_id}/?format=json&child_cases__full=true" ->
            body = Test.Fixtures.case_response("nj-covid-camden", duplicate_1_case_id)
            {:ok, %{body: body, status_code: 200, request_url: url}}

          url == "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/#{duplicate_2_case_id}/?format=json&child_cases__full=true" ->
            body = Test.Fixtures.case_response("nj-covid-camden", duplicate_2_case_id)
            {:ok, %{body: body, status_code: 200, request_url: url}}
        end
      end)

      set_up_index_case(%{case_id: terminal_case_id})
      set_up_index_case(%{case_id: duplicate_2_case_id, data: %{duplicate_of_case_id: terminal_case_id}})

      set_up_index_case(%{
        case_id: duplicate_1_case_id,
        data: %{transfer_source_case_id: "source-case-id", duplicate_of_case_id: duplicate_2_case_id}
      })

      set_up_index_case(%{case_id: "source-case-id", data: %{external_id: "1234567"}})

      case_identifier =
        CaseIdentifier.new(
          transfer_source_case_id: "source-case-id",
          external_id: "1234567",
          county_domain: "nj-covid-camden"
        )

      {:ok, case} = CaseTransferChain.fetch_case(case_identifier)
      assert %{"case_id" => ^terminal_case_id} = case
    end

    test "when the duplicate chain has a cycle, it just picks one of the cases" do
      duplicate_1_case_id = "duplicate-cycle-1"
      duplicate_2_case_id = "duplicate-cycle-2"

      NYSETL.HTTPoisonMock
      |> stub(:get, fn url, _headers, _opts ->
        cond do
          url == "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/?external_id=1234567" ->
            body = Test.Fixtures.case_external_id_response("empty_result", "1234567")
            {:ok, %{body: body, status_code: 200, request_url: url}}

          url == "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/#{duplicate_1_case_id}/?format=json&child_cases__full=true" ->
            body = Test.Fixtures.case_response("nj-covid-camden", duplicate_1_case_id)
            {:ok, %{body: body, status_code: 200, request_url: url}}

          url == "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/#{duplicate_2_case_id}/?format=json&child_cases__full=true" ->
            body = Test.Fixtures.case_response("nj-covid-camden", duplicate_2_case_id)
            {:ok, %{body: body, status_code: 200, request_url: url}}
        end
      end)

      set_up_index_case(%{case_id: duplicate_2_case_id, data: %{duplicate_of_case_id: duplicate_1_case_id}})

      set_up_index_case(%{
        case_id: duplicate_1_case_id,
        data: %{transfer_source_case_id: "source-case-id", duplicate_of_case_id: duplicate_2_case_id}
      })

      set_up_index_case(%{case_id: "source-case-id", data: %{external_id: "1234567"}})

      case_identifier =
        CaseIdentifier.new(
          transfer_source_case_id: "source-case-id",
          external_id: "1234567",
          county_domain: "nj-covid-camden"
        )

      {:ok, case} = CaseTransferChain.fetch_case(case_identifier)
      assert %{"case_id" => ^duplicate_2_case_id} = case
    end

    test "when the duplicate chain dead ends, it just returns the last available case" do
      dead_end_duplicate_id = "dead-end-duplicate"

      NYSETL.HTTPoisonMock
      |> stub(:get, fn url, _headers, _opts ->
        cond do
          url == "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/?external_id=1234567" ->
            body = Test.Fixtures.case_external_id_response("empty_result", "1234567")
            {:ok, %{body: body, status_code: 200, request_url: url}}

          url == "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/#{dead_end_duplicate_id}/?format=json&child_cases__full=true" ->
            body = Test.Fixtures.case_response("nj-covid-camden", dead_end_duplicate_id)
            {:ok, %{body: body, status_code: 200, request_url: url}}

          url == "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/missing-duplicate-terminal-case/?format=json&child_cases__full=true" ->
            {:ok, %{body: "", status_code: 404, request_url: url}}
        end
      end)

      set_up_index_case(%{case_id: dead_end_duplicate_id, data: %{transfer_source_case_id: "source-case-id"}})
      set_up_index_case(%{case_id: "source-case-id", data: %{external_id: "1234567"}})

      case_identifier =
        CaseIdentifier.new(
          transfer_source_case_id: "source-case-id",
          external_id: "1234567",
          county_domain: "nj-covid-camden"
        )

      {:ok, case} = CaseTransferChain.fetch_case(case_identifier)
      assert %{"case_id" => ^dead_end_duplicate_id} = case
    end
  end

  describe "fetch case when there are multiple transfer cases that match on external_id, but none with a matching transfer_source_case_id" do
    test "it attempts to match just on transfer_source_case_id" do
      terminal_case_id = "12345678-1234-1234-1234-123456789012"
      duplicate_2_case_id = "duplicate-2"

      NYSETL.HTTPoisonMock
      |> stub(:get, fn url, _headers, _opts ->
        cond do
          url == "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/?external_id=1234567" ->
            body = Test.Fixtures.case_external_id_response("multiple_external_id_matches_without_transfer_source_case_id_match", "1234567")
            {:ok, %{body: body, status_code: 200, request_url: url}}

          url == "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/#{terminal_case_id}/?format=json&child_cases__full=true" ->
            body = Test.Fixtures.case_response("nj-covid-camden", terminal_case_id)
            {:ok, %{body: body, status_code: 200, request_url: url}}

          url == "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/#{duplicate_2_case_id}/?format=json&child_cases__full=true" ->
            body = Test.Fixtures.case_response("nj-covid-camden", duplicate_2_case_id)
            {:ok, %{body: body, status_code: 200, request_url: url}}
        end
      end)

      set_up_index_case(%{case_id: terminal_case_id})
      set_up_index_case(%{case_id: duplicate_2_case_id, data: %{transfer_source_case_id: "source-case-id"}})
      set_up_index_case(%{case_id: "source-case-id", data: %{external_id: "1234567"}})

      case_identifier =
        CaseIdentifier.new(
          transfer_source_case_id: "source-case-id",
          external_id: "1234567",
          county_domain: "nj-covid-camden"
        )

      {:ok, case} = CaseTransferChain.fetch_case(case_identifier)
      assert %{"case_id" => ^terminal_case_id} = case
    end
  end

  describe "fetch_case: when a transfer source is missing its external_id, it looks in the Viaduct DB for a matching transfer_source_case_id" do
    test "when there's a single matching case and it exists in commcare, we return the case" do
      destination_case_id = "12345678-1234-1234-1234-123456789012"

      NYSETL.HTTPoisonMock
      |> stub(
        :get,
        fn "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/12345678-1234-1234-1234-123456789012/?format=json&child_cases__full=true" = url,
           _headers,
           _opts ->
          body = Test.Fixtures.case_response("nj-covid-camden", "12345678-1234-1234-1234-123456789012")
          {:ok, %{body: body, status_code: 200, request_url: url}}
        end
      )

      set_up_index_case(%{case_id: destination_case_id, data: %{transfer_source_case_id: "source-case-id"}})
      set_up_index_case(%{data: %{transfer_source_case_id: "non-matching-id"}})

      case_identifier =
        CaseIdentifier.new(
          transfer_source_case_id: "source-case-id",
          external_id: nil,
          county_domain: "nj-covid-camden"
        )

      {:ok, case} = CaseTransferChain.fetch_case(case_identifier)
      assert %{"case_id" => "12345678-1234-1234-1234-123456789012"} = case
    end

    test "when there's a single matching case in our DB and it does not exist in CommcCare, it returns :no_cases_match" do
      destination_case_id = "12345678-1234-1234-1234-123456789012"

      NYSETL.HTTPoisonMock
      |> stub(
        :get,
        fn "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/12345678-1234-1234-1234-123456789012/?format=json&child_cases__full=true" = url,
           _headers,
           _opts ->
          {:ok, %{body: "", status_code: 404, request_url: url}}
        end
      )

      set_up_index_case(%{case_id: destination_case_id, data: %{transfer_source_case_id: "source-case-id"}})
      set_up_index_case(%{data: %{transfer_source_case_id: "non-matching-id"}})

      case_identifier =
        CaseIdentifier.new(
          transfer_source_case_id: "source-case-id",
          external_id: nil,
          county_domain: "nj-covid-camden"
        )

      assert {:no_case_matches, {"source-case-id", []}} = CaseTransferChain.fetch_case(case_identifier)
    end

    test "when there is not a matching case in our DB, it returns :no_case_matches" do
      set_up_index_case(%{data: %{transfer_source_case_id: "non-matching-id"}})

      case_identifier =
        CaseIdentifier.new(
          transfer_source_case_id: "source-case-id",
          external_id: nil,
          county_domain: "nj-covid-camden"
        )

      assert {:no_case_matches, {"source-case-id", []}} = CaseTransferChain.fetch_case(case_identifier)
    end

    test "when there is more than one matching case in our DB, it returns :more_than_one" do
      case_1 = set_up_index_case(%{data: %{transfer_source_case_id: "source-case-id"}})
      case_2 = set_up_index_case(%{data: %{transfer_source_case_id: "source-case-id"}})

      case_identifier =
        CaseIdentifier.new(
          transfer_source_case_id: "source-case-id",
          external_id: nil,
          county_domain: "nj-covid-camden"
        )

      {:more_than_one, [%{case_id: case_1_id}, %{case_id: case_2_id}]} = CaseTransferChain.fetch_case(case_identifier)
      assert MapSet.new([case_1.case_id, case_2.case_id]) == MapSet.new([case_1_id, case_2_id])
    end
  end

  defp set_up_index_case(attrs) do
    {:ok, _county} = ECLRS.find_or_create_county(111)
    {:ok, person} = %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.create_person()

    {:ok, index_case} =
      %{data: %{a: 1}, person_id: person.id, county_id: 111}
      |> Map.merge(attrs)
      |> Commcare.create_index_case()

    index_case
  end
end
