defmodule NYSETL.Commcare.ApiTest do
  use NYSETL.DataCase, async: false

  alias NYSETL.Commcare
  alias NYSETL.Test

  describe "get_county_list" do
    setup :set_mox_from_context
    setup :mock_county_list

    test "returns list of counties" do
      {:ok, counties, :cache_skip} = Commcare.Api.get_county_list()
      assert length(counties) == 65
      assert counties |> Enum.map(& &1["fixture_type"]) |> Enum.uniq() == ["county_list"]
    end

    test "caches the results" do
      Cachex.clear(:cache)

      {:ok, _counties, :cache_miss} = Commcare.Api.get_county_list(:cache_enabled)
      {:ok, _counties, :cache_hit} = Commcare.Api.get_county_list(:cache_enabled)

      Cachex.clear(:cache)

      {:ok, _counties, :cache_miss} = Commcare.Api.get_county_list(:cache_enabled)
    end
  end

  describe "post_case" do
    test "handles success response" do
      NYSETL.HTTPoisonMock
      |> expect(:post, fn "http://commcare.test.host/a/uk-midsomer-cdcms/receiver/", "<xml>" = _body, _headers ->
        {:ok, %{status_code: 201, body: Test.Fixtures.commcare_submit_response(:success)}}
      end)

      assert {:ok, response} = Commcare.Api.post_case("<xml>", Test.Fixtures.test_county_1_domain())
      assert response.body =~ "submit_success"
    end

    test "handles error response" do
      NYSETL.HTTPoisonMock
      |> expect(:post, fn "http://commcare.test.host/a/uk-midsomer-cdcms/receiver/", "<xml>" = _body, _headers ->
        {:ok, %{status_code: 201, body: Test.Fixtures.commcare_submit_response(:error)}}
      end)

      assert {:error, response} = Commcare.Api.post_case("<xml>", Test.Fixtures.test_county_1_domain())
      assert response.body =~ "submit_error"
    end

    test "handles rate limit response" do
      NYSETL.HTTPoisonMock
      |> expect(:post, fn "http://commcare.test.host/a/uk-midsomer-cdcms/receiver/", "<xml>" = _body, _headers ->
        {:ok, %{status_code: 429, body: Test.Fixtures.commcare_submit_response(:error)}}
      end)

      assert {:error, :rate_limited} = Commcare.Api.post_case("<xml>", Test.Fixtures.test_county_1_domain())
    end

    test "handles other status codes that aren't HttpPoison errors" do
      NYSETL.HTTPoisonMock
      |> expect(:post, fn "http://commcare.test.host/a/uk-midsomer-cdcms/receiver/", "<xml>" = _body, _headers ->
        {:ok, %{status_code: 202, body: "some other semi-successful error"}}
      end)

      assert {:error, %{status_code: 202, body: "some other semi-successful error"}} =
               Commcare.Api.post_case("<xml>", Test.Fixtures.test_county_1_domain())
    end

    test "handles error responses" do
      NYSETL.HTTPoisonMock
      |> expect(:post, fn "http://commcare.test.host/a/uk-midsomer-cdcms/receiver/", "<xml>" = _body, _headers ->
        {:error, %{status_code: 500, body: "definitely an error"}}
      end)

      assert {:error, %{status_code: 500, body: "definitely an error"}} = Commcare.Api.post_case("<xml>", Test.Fixtures.test_county_1_domain())
    end
  end

  describe "get_case" do
    test "gets a case using case_id" do
      url = "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/12345678-1234-1234-1234-123456789012/?format=json&child_cases__full=true"

      NYSETL.HTTPoisonMock
      |> stub(:get, fn ^url, _headers, _opts ->
        body = Test.Fixtures.case_response("nj-covid-camden", "12345678-1234-1234-1234-123456789012")
        {:ok, %{body: body, status_code: 200, request_url: url}}
      end)

      assert {:ok, response} = Commcare.Api.get_case(commcare_case_id: Test.Fixtures.commcare_case_id(), county_domain: Test.Fixtures.county_domain())
      response |> Map.get("case_id") |> assert_eq(Test.Fixtures.commcare_case_id())
    end

    test "returns {:error, :not_found} when the case is not found" do
      url = "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/non-existent-case/?format=json&child_cases__full=true"

      NYSETL.HTTPoisonMock
      |> stub(:get, fn ^url, _headers, _opts ->
        {:ok, %{body: "", status_code: 404, request_url: url}}
      end)

      Commcare.Api.get_case(commcare_case_id: "non-existent-case", county_domain: Test.Fixtures.county_domain())
      |> assert_eq({:error, :not_found})
    end

    test "returns {:error, :rate_limited} when the result is :ok but the status code is not 429" do
      url = "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/12345678-1234-1234-1234-123456789012/?format=json&child_cases__full=true"

      NYSETL.HTTPoisonMock
      |> stub(:get, fn ^url, _headers, _opts ->
        {:ok, %{body: "Too many!", status_code: 429, request_url: url}}
      end)

      assert {:error, :rate_limited} =
               Commcare.Api.get_case(commcare_case_id: Test.Fixtures.commcare_case_id(), county_domain: Test.Fixtures.county_domain())
    end

    test "returns {:error, _} when the result is :ok but the status code is not 404 or 200" do
      url = "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/12345678-1234-1234-1234-123456789012/?format=json&child_cases__full=true"
      response = %{body: "Error!", status_code: 500, request_url: url}

      NYSETL.HTTPoisonMock
      |> stub(:get, fn ^url, _headers, _opts ->
        {:ok, response}
      end)

      assert {:error, ^response} =
               Commcare.Api.get_case(commcare_case_id: Test.Fixtures.commcare_case_id(), county_domain: Test.Fixtures.county_domain())
    end

    test "returns {:error, _} when the result is :error " do
      url = "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/12345678-1234-1234-1234-123456789012/?format=json&child_cases__full=true"
      response = %{body: "Error!", status_code: 501, request_url: url}

      NYSETL.HTTPoisonMock
      |> stub(:get, fn ^url, _headers, _opts ->
        {:error, response}
      end)

      assert {:error, ^response} =
               Commcare.Api.get_case(commcare_case_id: Test.Fixtures.commcare_case_id(), county_domain: Test.Fixtures.county_domain())
    end
  end

  describe "get_cases" do
    setup do
      NYSETL.HTTPoisonMock
      |> stub(:get, fn
        "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/?child_cases__full=true&type=patient&limit=100&offset=0", _headers, _options ->
          {:ok, %{status_code: 200, body: ~s|{"objects":["case has children"],"meta":{"next":null}}|}}

        "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/?server_date_modified_start=2013-09-29&type=patient&limit=100&offset=0",
        _headers,
        _options ->
          {:ok, %{status_code: 200, body: ~s|{"objects":["case after 2013-09-29T10:40Z"],"meta":{"next":null}}|}}

        "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/?type=patient&limit=100&offset=" <> offset = url, _headers, _opts ->
          body = Test.Fixtures.cases_response("nj-covid-camden", "patient", offset)
          {:ok, %{body: body, status_code: 200, request_url: url}}
      end)

      :ok
    end

    test "gets a page of cases for the given type from offset" do
      assert {:ok, response} = Commcare.Api.get_cases(county_domain: Test.Fixtures.county_domain(), type: "patient")

      response
      |> Map.get("next_offset")
      |> assert_eq(100)

      response
      |> Map.get("objects")
      |> Enum.map(fn case -> case["case_id"] end)
      |> assert_eq(["commcare_case_id_1", "commcare_case_id_2", "commcare_case_id_3"])
    end

    test "gets a page of cases for the given type after server modified at" do
      assert {:ok, response} = Commcare.Api.get_cases(county_domain: Test.Fixtures.county_domain(), type: "patient", modified_since: ~D[2013-09-29])

      response
      |> Map.get("objects")
      |> assert_eq(["case after 2013-09-29T10:40Z"])
    end

    test "optionally includes child cases" do
      assert {:ok, response} = Commcare.Api.get_cases(county_domain: Test.Fixtures.county_domain(), type: "patient", full: true)

      response
      |> Map.get("objects")
      |> assert_eq(["case has children"])
    end

    test "when there are no more pages to fetch, next_offset is nil" do
      assert {:ok, response} = Commcare.Api.get_cases(county_domain: Test.Fixtures.county_domain(), type: "patient", offset: 100)

      response
      |> Map.get("next_offset")
      |> assert_eq(nil)

      response
      |> Map.get("objects")
      |> Enum.map(fn case -> case["case_id"] end)
      |> assert_eq(["commcare_case_id_4"])
    end
  end

  describe "get_transfer_cases" do
    test "gets a case using external_id" do
      NYSETL.HTTPoisonMock
      |> stub(:get, fn "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/?external_id=1234567" = url, _headers, _opts ->
        body = Test.Fixtures.case_external_id_response("nj-covid-camden", "1234567")
        {:ok, %{body: body, status_code: 200, request_url: url}}
      end)

      assert {:ok, [response]} =
               Commcare.Api.get_transfer_cases(external_id: Test.Fixtures.external_id(), county_domain: Test.Fixtures.county_domain())

      response |> Map.get("properties") |> Map.get("external_id") |> assert_eq(Test.Fixtures.external_id())
    end
  end

  describe "get_case_list" do
    setup do
      NYSETL.HTTPoisonMock
      |> stub(:get, fn "http://commcare.test.host/a/nj-covid-camden/api/v0.5/case/?owner_id=1234567890" = url, _headers, _options ->
        body = Test.Fixtures.case_list_response("nj-covid-camden", "1234567890")
        {:ok, %{body: body, status_code: 200, request_url: url}}
      end)

      :ok
    end

    test "gets list of cases for given county" do
      assert {:ok, response} = Commcare.Api.get_case_list(owner_id: Test.Fixtures.owner_id(), county_domain: Test.Fixtures.county_domain())

      response |> Jason.decode!() |> Map.get("objects") |> length() |> assert_eq(2)
    end
  end

  describe "ping" do
    setup do
      NYSETL.HTTPoisonMock
      |> stub(:get, fn "http://commcare.test.host/accounts/login/" = _url, _headers, _options ->
        {:ok, %{body: "", status_code: 200}}
      end)

      :ok
    end

    test "returns an ok tuple for a successful request to commcare" do
      assert {:ok, _} = Commcare.Api.ping()
    end
  end
end
