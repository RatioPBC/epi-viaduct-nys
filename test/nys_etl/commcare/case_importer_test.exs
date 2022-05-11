defmodule NYSETL.Commcare.CaseImporterTest do
  use NYSETL.DataCase, async: false
  use Oban.Testing, repo: NYSETL.Repo

  import NYSETL.Test.TestHelpers

  alias NYSETL.Commcare
  alias NYSETL.Commcare.CaseImporter
  alias NYSETL.ECLRS
  alias NYSETL.Test

  @user_id "2753ce1d42654b9897a3f88493838e34"

  def fixture(properties) when is_map(properties) do
    case_id = Ecto.UUID.generate()

    patient_case = %{
      "case_id" => case_id,
      "child_cases" => %{},
      "closed" => false,
      "date_closed" => nil,
      "date_modified" => "2020-06-04T13:43:10.375000Z",
      "domain" => "ny-somecounty-cdcms",
      "id" => case_id,
      "indexed_on" => "2020-06-04T13:43:10.907506",
      "indices" => %{},
      "opened_by" => "b08d0661a6fd40a3b2be2cc0d2760a8a",
      "properties" => Map.merge(%{"case_type" => "patient"}, properties),
      "resource_uri" => "",
      "server_date_modified" => "2020-06-04T13:43:10.465497Z",
      "server_date_opened" => "2020-06-01T18:55:09.622249Z",
      "user_id" => @user_id,
      "xform_ids" => ["01a5fc86-6572-40a2-a2c8-26ab09a8e05c", "52ef5142-6df7-473f-8a9d-58af58d7f4ca"]
    }

    {case_id, patient_case}
  end

  def with_child({case_id, case}, properties), do: {case_id, with_child(case, properties)}

  def with_child(case, properties) when is_map(properties) do
    {child_id, child} = fixture(properties)
    child = child |> Map.put("indices", %{"parent" => %{"case_id" => case["id"], "case_type" => "parent", "relationship" => "child"}})
    children = case["child_cases"] |> Map.put(child_id, child)
    case |> Map.put("child_cases", children)
  end

  setup do
    {:ok, _county} = ECLRS.find_or_create_county(12)

    county = %{
      display: "Some County",
      domain: "ny-somecounty-cdcms",
      fips: "12",
      gaz: "YAZ",
      location_id: "abc123456",
      name: "somecounty"
    }

    [county: county]
  end

  describe "perform (only commcare_case_id and domain provided)" do
    setup [:start_supervised_oban, :midsomer_county, :midsomer_patient_case]

    test "new cases fetch current case state and import", %{midsomer_county: midsomer, midsomer_patient_case: patient_case} do
      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/#{patient_case["case_id"]}/?format=json&child_cases__full=true"

        {:ok,
         %{
           status_code: 200,
           body: Jason.encode!(patient_case)
         }}
      end)

      assert {:error, :not_found} = Commcare.get_index_case(case_id: patient_case["case_id"], county_id: midsomer.fips)

      assert :ok = perform_job(CaseImporter, %{commcare_case_id: patient_case["case_id"], domain: midsomer.domain})
      assert {:ok, index_case} = Commcare.get_index_case(case_id: patient_case["case_id"], county_id: midsomer.fips)
      assert index_case.commcare_date_modified == ~U[2020-06-05T00:56:45.753000Z]
    end

    test "error when fetching fails for 404", %{midsomer_patient_case: patient_case, midsomer_county: midsomer} do
      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/#{patient_case["case_id"]}/?format=json&child_cases__full=true"

        {:ok,
         %{
           status_code: 404,
           body: Test.Fixtures.commcare_submit_response(:error)
         }}
      end)

      assert {:error, :not_found} = perform_job(CaseImporter, %{commcare_case_id: patient_case["case_id"], domain: midsomer.domain})
    end

    test "snooze when fetching fails because of rate limit", %{midsomer_county: midsomer, midsomer_patient_case: patient_case} do
      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/#{patient_case["case_id"]}/?format=json&child_cases__full=true"

        {:ok,
         %{
           status_code: 429,
           body: Test.Fixtures.commcare_submit_response(:error)
         }}
      end)

      assert {:snooze, 15} = perform_job(CaseImporter, %{commcare_case_id: patient_case["case_id"], domain: midsomer.domain})
    end

    test "update existing case by fetching CommCare API data", %{midsomer_county: midsomer} do
      {case_id, commcare_case} =
        fixture(%{
          "some" => "updated value",
          "another" => "new value"
        })

      commcare_case = Map.put(commcare_case, "domain", midsomer.domain)

      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/#{case_id}/?format=json&child_cases__full=true"

        {:ok,
         %{
           status_code: 200,
           body: Jason.encode!(commcare_case)
         }}
      end)

      {:ok, person} = Commcare.create_person(%{data: %{}, patient_keys: ["1234", "150000000"], name_first: nil, name_last: nil})

      {:ok, existing_index_case} =
        Commcare.create_index_case(%{case_id: case_id, data: %{"some" => "value", "other" => "stuff"}, person_id: person.id, county_id: midsomer.fips})

      refute existing_index_case.commcare_date_modified

      assert :ok =
               perform_job(CaseImporter, %{
                 commcare_case_id: case_id,
                 domain: midsomer.domain
               })

      updated_index_case = Repo.reload(existing_index_case)
      assert updated_index_case.data == %{"some" => "updated value", "other" => "stuff", "another" => "new value", "case_type" => "patient"}
      assert updated_index_case.commcare_date_modified == ~U[2020-06-04T13:43:10.375000Z]
    end

    test "doesn't update index case using old case data", %{midsomer_county: midsomer} do
      {case_id, commcare_case} =
        fixture(%{
          "external_id" => "9999#150000000",
          "first_name" => "Glen",
          "last_name" => "Livet",
          "other" => "thing"
        })

      commcare_case = Map.put(commcare_case, "domain", midsomer.domain)

      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/#{case_id}/?format=json&child_cases__full=true"

        {:ok,
         %{
           status_code: 200,
           body: Jason.encode!(commcare_case)
         }}
      end)

      {:ok, person} = Commcare.create_person(%{data: %{}, patient_keys: ["1234", "150000000"], name_first: nil, name_last: nil})

      {:ok, existing_index_case} =
        Commcare.create_index_case(%{
          case_id: case_id,
          data: %{"some" => "value", "other" => "stuff"},
          person_id: person.id,
          county_id: midsomer.fips,
          commcare_date_modified: ~U[2020-06-04T13:43:10.375000Z]
        })

      assert {:discard, :stale_data} =
               perform_job(CaseImporter, %{
                 commcare_case_id: case_id,
                 domain: midsomer.domain
               })

      updated_index_case = Repo.reload(existing_index_case)
      updated_index_case |> assert_events([])
      assert existing_index_case == updated_index_case
    end

    test "discard when missing required information (DOB)", %{midsomer_county: midsomer, midsomer_patient_case: patient_case} do
      patient_case = put_in(patient_case, ["properties", "dob"], "")

      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/#{patient_case["case_id"]}/?format=json&child_cases__full=true"

        {:ok,
         %{
           status_code: 200,
           body: Jason.encode!(patient_case)
         }}
      end)

      assert {:discard, [dob: _]} = perform_job(CaseImporter, %{commcare_case_id: patient_case["case_id"], domain: midsomer.domain})
    end
  end

  describe "perform (new params provided)" do
    setup [:start_supervised_oban, :midsomer_county, :midsomer_patient_case]

    test "import new cases from case forwarder data", %{midsomer_county: midsomer, midsomer_patient_case: patient_case} do
      patient_case = Map.delete(patient_case, "child_cases")

      assert {:error, :not_found} = Commcare.get_index_case(case_id: patient_case["case_id"], county_id: midsomer.fips)

      assert :ok = perform_job(CaseImporter, %{commcare_case: patient_case})
      assert {:ok, index_case} = Commcare.get_index_case(case_id: patient_case["case_id"], county_id: midsomer.fips)
      assert index_case.commcare_date_modified == ~U[2020-06-05T00:56:45.753000Z]
    end

    test "fetch API state when payload lacks required information", %{midsomer_county: midsomer, midsomer_patient_case: patient_case} do
      invalid_patient_case = put_in(patient_case, ["properties", "dob"], "")

      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/#{patient_case["case_id"]}/?format=json&child_cases__full=true"

        {:ok,
         %{
           status_code: 200,
           body: Jason.encode!(patient_case)
         }}
      end)

      assert {:error, :not_found} = Commcare.get_index_case(case_id: patient_case["case_id"], county_id: midsomer.fips)

      assert :ok = perform_job(CaseImporter, %{commcare_case: invalid_patient_case})
      assert {:ok, index_case} = Commcare.get_index_case(case_id: patient_case["case_id"], county_id: midsomer.fips)
      assert index_case.commcare_date_modified == ~U[2020-06-05T00:56:45.753000Z]
    end

    test "discard when payload and API lack required information (DOB)", %{midsomer_patient_case: patient_case} do
      invalid_patient_case = put_in(patient_case, ["properties", "dob"], "")

      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/#{patient_case["case_id"]}/?format=json&child_cases__full=true"

        {:ok,
         %{
           status_code: 200,
           body: Jason.encode!(invalid_patient_case)
         }}
      end)

      assert {:discard, [dob: _]} = perform_job(CaseImporter, %{commcare_case: invalid_patient_case})
    end

    test "snooze when API is stale compared to the payload", %{midsomer_county: midsomer, midsomer_patient_case: patient_case} do
      invalid_patient_case =
        patient_case
        |> put_in(["properties", "dob"], "")
        |> Map.put("date_modified", "2020-06-06T00:56:45.753000Z")

      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/#{patient_case["case_id"]}/?format=json&child_cases__full=true"

        {:ok,
         %{
           status_code: 200,
           body: Jason.encode!(patient_case)
         }}
      end)

      assert {:snooze, 180} = perform_job(CaseImporter, %{commcare_case: invalid_patient_case})
      assert {:error, :not_found} = Commcare.get_index_case(case_id: patient_case["case_id"], county_id: midsomer.fips)
    end

    test "snooze when fetching fails because of rate limit", %{midsomer_patient_case: patient_case} do
      invalid_patient_case = put_in(patient_case, ["properties", "dob"], "")

      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/#{patient_case["case_id"]}/?format=json&child_cases__full=true"

        {:ok,
         %{
           status_code: 429,
           body: Test.Fixtures.commcare_submit_response(:error)
         }}
      end)

      assert {:snooze, 15} = perform_job(CaseImporter, %{commcare_case: invalid_patient_case})
    end

    test "error when fetching fails for 404", %{midsomer_patient_case: patient_case} do
      invalid_patient_case = put_in(patient_case, ["properties", "dob"], "")

      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/#{patient_case["case_id"]}/?format=json&child_cases__full=true"

        {:ok,
         %{
           status_code: 404,
           body: Test.Fixtures.commcare_submit_response(:error)
         }}
      end)

      assert {:error, :not_found} = perform_job(CaseImporter, %{commcare_case: invalid_patient_case})
    end

    test "update existing case using case data", %{midsomer_county: midsomer} do
      {case_id, _commcare_case} =
        fixture(%{
          "external_id" => "9999#150000000",
          "first_name" => "Glen",
          "last_name" => "Livet",
          "other" => "thing"
        })

      {:ok, person} = Commcare.create_person(%{data: %{}, patient_keys: ["1234", "150000000"], name_first: nil, name_last: nil})

      {:ok, existing_index_case} =
        Commcare.create_index_case(%{case_id: case_id, data: %{"some" => "value", "other" => "stuff"}, person_id: person.id, county_id: midsomer.fips})

      refute existing_index_case.commcare_date_modified

      assert :ok =
               perform_job(CaseImporter, %{
                 commcare_case: %{
                   case_id: case_id,
                   domain: midsomer.domain,
                   date_modified: "2020-06-04T13:43:10.375000Z",
                   properties: %{"some" => "updated value", "another" => "new value", "case_type" => "patient"}
                 }
               })

      updated_index_case = Repo.reload(existing_index_case)
      assert updated_index_case.data == %{"some" => "updated value", "other" => "stuff", "another" => "new value", "case_type" => "patient"}
      assert updated_index_case.commcare_date_modified == ~U[2020-06-04T13:43:10.375000Z]
    end

    test "discard stale case data", %{midsomer_county: midsomer} do
      case_id = "fake-case-id"

      {:ok, person} = Commcare.create_person(%{data: %{}, patient_keys: ["1234", "150000000"], name_first: nil, name_last: nil})

      {:ok, existing_index_case} =
        Commcare.create_index_case(%{
          case_id: case_id,
          data: %{"some" => "value", "other" => "stuff"},
          person_id: person.id,
          county_id: midsomer.fips,
          commcare_date_modified: ~U[2020-06-04T13:43:10.375000Z]
        })

      assert {:discard, :stale_data} =
               perform_job(CaseImporter, %{
                 commcare_case: %{
                   case_id: case_id,
                   domain: midsomer.domain,
                   date_modified: "2020-06-04T12:00:00.000000Z",
                   properties: %{"some" => "updated value", "another" => "new value", "case_type" => "patient"}
                 }
               })

      updated_index_case = Repo.reload(existing_index_case)
      updated_index_case |> assert_events([])
      assert existing_index_case == updated_index_case
    end
  end

  describe "import_case(:create)" do
    setup [:midsomer_county]

    test "returns :ok and creates a Person when no Person exists that matches case", context do
      {first_name, last_name, dob} = {"Glen", "Livet", "2001-01-02"}

      {case_id, patient_case} =
        fixture(%{
          "first_name" => first_name,
          "last_name" => last_name,
          "dob" => dob,
          "some" => "value"
        })

      assert {:error, :not_found} = Commcare.get_person(dob: dob, name_first: "GLEN", name_last: "LIVET")
      assert {:error, :not_found} = Commcare.get_index_case(case_id: case_id, county_id: context.county.fips)

      assert :ok = CaseImporter.import_case(:create, case: patient_case, county: context.county)

      assert {:ok, index_case} = Commcare.get_index_case(case_id: case_id, county_id: context.county.fips)
      assert {:ok, person} = Commcare.get_person(dob: dob, name_first: "GLEN", name_last: "LIVET")
      assert_eq(index_case.person_id, person.id)

      assert_eq(index_case.data, %{
        "first_name" => "Glen",
        "last_name" => "Livet",
        "dob" => dob,
        "some" => "value",
        "case_type" => "patient"
      })

      assert_eq([], person.patient_keys)
    end

    test "returns :ok when a Person can by found by patient_key extracted from a case", context do
      {:ok, person} = Commcare.create_person(%{data: %{}, patient_keys: ["1234", "150000000"], name_first: nil, name_last: nil})

      {case_id, commcare_case} =
        fixture(%{
          "external_id" => "9999#150000000",
          "first_name" => "Glen",
          "last_name" => "Livet"
        })

      assert :ok = CaseImporter.import_case(:create, case: commcare_case, county: context.county)

      assert {:ok, index_case} = Commcare.get_index_case(case_id: case_id, county_id: context.county.fips)

      index_case.case_id |> assert_eq(case_id)
      index_case.county_id |> assert_eq(12)
      index_case.person_id |> assert_eq(person.id)

      index_case |> assert_events(["retrieved_from_commcare"])
    end

    test "returns :ok when a Person can by found by dob and name extracted from a case", context do
      {:ok, person} =
        Commcare.create_person(%{
          data: %{},
          patient_keys: ["1234"],
          name_first: "GLEN",
          name_last: "LIVET",
          dob: ~D[2008-01-01]
        })

      {case_id, commcare_case} =
        fixture(%{
          "external_id" => "9999",
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2008-01-01"
        })

      assert :ok = CaseImporter.import_case(:create, case: commcare_case, county: context.county)

      assert {:ok, index_case} = Commcare.get_index_case(case_id: case_id, county_id: context.county.fips)

      index_case.case_id |> assert_eq(case_id)
      index_case.county_id |> assert_eq(12)
      index_case.person_id |> assert_eq(person.id)

      index_case |> assert_events(["retrieved_from_commcare"])
    end

    test "returns :ok when a Person can by found by dob and full_name extracted from a case", context do
      {:ok, person} =
        Commcare.create_person(%{
          data: %{},
          patient_keys: ["1234"],
          name_first: "GLEN",
          name_last: "LIVET JONES",
          dob: ~D[2008-01-02]
        })

      {case_id, commcare_case} =
        fixture(%{
          "full_name" => "GLEN LIVET JONES",
          "dob" => "2008-01-02"
        })

      assert :ok = CaseImporter.import_case(:create, case: commcare_case, county: context.county)

      assert {:ok, index_case} = Commcare.get_index_case(case_id: case_id, county_id: context.county.fips)

      index_case.case_id |> assert_eq(case_id)
      index_case.county_id |> assert_eq(12)
      index_case.person_id |> assert_eq(person.id)

      index_case |> assert_events(["retrieved_from_commcare"])
    end

    test "creates lab results when creating an index case", context do
      {:ok, _person} = Commcare.create_person(%{data: %{}, patient_keys: ["1234"]})

      {case_id, commcare_case} =
        fixture(%{
          "external_id" => "9999#1234",
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2008-01-01"
        })
        |> with_child(%{
          "accession_number" => "ABC100001",
          "analysis_date" => "2020-05-22",
          "case_name" => " lab_result",
          "case_type" => "lab_result",
          "date_opened" => "2020-06-04T00:00:00.000000Z",
          "doh_mpi_id" => "9999",
          "external_id" => "9999#1234#ABC100001",
          "lab_result" => "positive",
          "laboratory" => "Access DX Laboratory, LLC",
          "owner_id" => @user_id,
          "specimen_collection_date" => "2020-05-22",
          "specimen_source" => "Nasopharyngeal Swab",
          "test_type" => "SARS coronavirus 2 RNA [Presence] in Unspecified s"
        })

      assert :ok = CaseImporter.import_case(:create, case: commcare_case, county: context.county)

      assert {:ok, index_case} = Commcare.get_index_case(case_id: case_id, county_id: context.county.fips)

      [lab_result] = index_case |> Repo.preload(:lab_results) |> Map.get(:lab_results)
      lab_result.case_id |> assert_eq(commcare_case["child_cases"] |> Map.keys() |> List.first())
      lab_result.accession_number |> assert_eq("ABC100001")

      lab_result.data
      |> assert_eq(%{
        "accession_number" => "ABC100001",
        "analysis_date" => "2020-05-22",
        "case_name" => " lab_result",
        "case_type" => "lab_result",
        "date_opened" => "2020-06-04T00:00:00.000000Z",
        "doh_mpi_id" => "9999",
        "external_id" => "9999#1234#ABC100001",
        "lab_result" => "positive",
        "laboratory" => "Access DX Laboratory, LLC",
        "owner_id" => @user_id,
        "specimen_collection_date" => "2020-05-22",
        "specimen_source" => "Nasopharyngeal Swab",
        "test_type" => "SARS coronavirus 2 RNA [Presence] in Unspecified s"
      })
    end

    test "creates lab results when creating a new person", context do
      {case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2008-01-01"
        })
        |> with_child(%{
          "accession_number" => "ABC100001",
          "analysis_date" => "2020-05-22",
          "case_name" => " lab_result",
          "case_type" => "lab_result",
          "date_opened" => "2020-06-04T00:00:00.000000Z",
          "doh_mpi_id" => "9999",
          "external_id" => "9999#1234#ABC100001",
          "lab_result" => "positive",
          "laboratory" => "Access DX Laboratory, LLC",
          "owner_id" => @user_id,
          "specimen_collection_date" => "2020-05-22",
          "specimen_source" => "Nasopharyngeal Swab",
          "test_type" => "SARS coronavirus 2 RNA [Presence] in Unspecified s"
        })

      assert :ok = CaseImporter.import_case(:create, case: patient_case, county: context.county)
      assert {:ok, index_case} = Commcare.get_index_case(case_id: case_id, county_id: context.county.fips)

      [lab_result] = index_case |> Repo.preload(:lab_results) |> Map.get(:lab_results)
      lab_result.case_id |> assert_eq(patient_case["child_cases"] |> Map.keys() |> List.first())
      lab_result.accession_number |> assert_eq("ABC100001")

      lab_result.data
      |> assert_eq(%{
        "accession_number" => "ABC100001",
        "analysis_date" => "2020-05-22",
        "case_name" => " lab_result",
        "case_type" => "lab_result",
        "date_opened" => "2020-06-04T00:00:00.000000Z",
        "doh_mpi_id" => "9999",
        "external_id" => "9999#1234#ABC100001",
        "lab_result" => "positive",
        "laboratory" => "Access DX Laboratory, LLC",
        "owner_id" => @user_id,
        "specimen_collection_date" => "2020-05-22",
        "specimen_source" => "Nasopharyngeal Swab",
        "test_type" => "SARS coronavirus 2 RNA [Presence] in Unspecified s"
      })
    end

    test "skips lab results with no accession number", context do
      {:ok, _person} = Commcare.create_person(%{data: %{}, patient_keys: ["1234"]})

      {case_id, commcare_case} =
        fixture(%{
          "external_id" => "9999#1234",
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2008-01-01"
        })
        |> with_child(%{
          "analysis_date" => "2020-05-22",
          "case_name" => " lab_result",
          "case_type" => "lab_result",
          "date_opened" => "2020-06-04T00:00:00.000000Z",
          "doh_mpi_id" => "",
          "external_id" => nil,
          "lab_result" => "positive",
          "laboratory" => "",
          "owner_id" => @user_id,
          "specimen_collection_date" => "2020-05-22",
          "specimen_source" => "Nasopharyngeal",
          "test_type" => "PCR"
        })

      assert :ok = CaseImporter.import_case(:create, case: commcare_case, county: context.county)

      assert {:ok, index_case} = Commcare.get_index_case(case_id: case_id, county_id: context.county.fips)

      index_case
      |> Repo.preload(:lab_results)
      |> Map.get(:lab_results)
      |> assert_eq([])
    end

    test "discard when index case already exists (possible if case forwarder sends multiple creates, or imported via transfer)", context do
      {case_id, commcare_case} =
        fixture(%{
          "external_id" => "9999#150000000",
          "first_name" => "Glen",
          "last_name" => "Livet",
          "other" => "thing"
        })

      {:ok, person} = Commcare.create_person(%{data: %{}, patient_keys: ["1234", "150000000"], name_first: nil, name_last: nil})

      {:ok, _existing_index_case} =
        Commcare.create_index_case(%{case_id: case_id, data: %{"some" => "value", "other" => "stuff"}, person_id: person.id, county_id: 12})

      assert {:discard, _} = CaseImporter.import_case(:create, case: commcare_case, county: context.county)
    end
  end

  describe "import_case(:update)" do
    setup [:midsomer_county]

    test "returns :ok and updates the index case when one already exists for that case id and county", context do
      {case_id, commcare_case} =
        fixture(%{
          "external_id" => "9999#150000000",
          "first_name" => "Glen",
          "last_name" => "Livet",
          "other" => "thing"
        })

      {:ok, person} = Commcare.create_person(%{data: %{}, patient_keys: ["1234", "150000000"], name_first: nil, name_last: nil})

      {:ok, existing_index_case} =
        Commcare.create_index_case(%{case_id: case_id, data: %{"some" => "value", "other" => "stuff"}, person_id: person.id, county_id: 12})

      assert :ok = CaseImporter.import_case(:update, case: commcare_case, county: context.county)
      updated_index_case = Repo.reload(existing_index_case)

      updated_index_case.case_id |> assert_eq(case_id)
      updated_index_case.county_id |> assert_eq(12)
      updated_index_case.person_id |> assert_eq(person.id)

      updated_index_case.data
      |> assert_eq(%{
        "external_id" => "9999#150000000",
        "first_name" => "Glen",
        "last_name" => "Livet",
        "some" => "value",
        "other" => "thing",
        "case_type" => "patient"
      })

      updated_index_case |> assert_events(["updated_from_commcare"])
    end

    test "doesn't update index case using old case data", %{midsomer_county: midsomer} do
      {case_id, commcare_case} =
        fixture(%{
          "external_id" => "9999#150000000",
          "first_name" => "Glen",
          "last_name" => "Livet",
          "other" => "thing"
        })

      {:ok, person} = Commcare.create_person(%{data: %{}, patient_keys: ["1234", "150000000"], name_first: nil, name_last: nil})

      {:ok, existing_index_case} =
        Commcare.create_index_case(%{
          case_id: case_id,
          data: %{"some" => "value", "other" => "stuff"},
          person_id: person.id,
          county_id: midsomer.fips,
          commcare_date_modified: ~U[2020-06-04T13:43:10.375000Z]
        })

      assert {:discard, :stale_data} = CaseImporter.import_case(:update, case: commcare_case, county: midsomer)
      updated_index_case = Repo.reload(existing_index_case)
      updated_index_case |> assert_events([])
      assert existing_index_case == updated_index_case
    end
  end

  describe "process - CommCare exclusion filters for cases not yet imported" do
    test "skips index cases where properties[final_disposition] IN (registered_in_error,duplicate,not_a_case)", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "final_disposition" => "registered_in_error"
        })

      assert {:discard, :final_disposition} = CaseImporter.import_case(:create, case: patient_case, county: context.county)

      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "final_disposition" => "duplicate"
        })

      assert {:discard, :final_disposition} = CaseImporter.import_case(:create, case: patient_case, county: context.county)

      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "final_disposition" => "not_a_case"
        })

      assert {:discard, :final_disposition} = CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end

    test "skips excluded index cases when the person is already known", context do
      {:ok, _person} = Commcare.create_person(%{data: %{}, patient_keys: [], name_first: "GLEN", name_last: "LIVET", dob: "2000-01-02"})

      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "final_disposition" => "registered_in_error"
        })

      assert {:discard, :final_disposition} = CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end

    test "returns :ok for any other final_disposition", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "final_disposition" => "something_else"
        })

      assert :ok = CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end

    test "skips index cases where properties[stub]=yes", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "stub" => "yes"
        })

      assert {:discard, :stub} = CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end

    test "returns :ok for any other stub", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "stub" => "no"
        })

      assert :ok = CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end

    test "skips index cases where closed=true (at the top-level)", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02"
        })

      patient_case = Map.put(patient_case, "closed", true)

      assert {:discard, :closed} = CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end

    test "returns :ok for any other closed (at the top-level)", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02"
        })

      patient_case = Map.put(patient_case, "closed", nil)

      assert :ok = CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end

    test "skips index cases where current_status=closed and patient_type=pui", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "current_status" => "closed",
          "patient_type" => "pui"
        })

      assert {:discard, :closed} = CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end

    test "imports index cases where current_status=open and patient_type=pui", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "current_status" => "open",
          "patient_type" => "pui"
        })

      assert :ok = CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end

    test "imports index cases where current_status=closed and patient_type=confirmed", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "current_status" => "closed",
          "patient_type" => "confirmed"
        })

      assert :ok = CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end

    test "skips index cases where transfer_status IN (pending,sent)", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "transfer_status" => "pending"
        })

      assert {:discard, :transfer_status} = CaseImporter.import_case(:create, case: patient_case, county: context.county)

      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "transfer_status" => "sent"
        })

      assert {:discard, :transfer_status} = CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end

    test "imports index cases where for any other transfer_status", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "transfer_status" => "something_else"
        })

      assert :ok = CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end

    test "skips index cases where the person has incomplete (name, DOB) or patient_key information", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "",
          "last_name" => "",
          "dob" => "2000-01-02"
        })

      assert {:discard, [name_first: {"can't be blank", [validation: :required]}, name_last: {"can't be blank", [validation: :required]}]} =
               CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end

    test "skips index cases with missing identifier information (even though patient_key is set - should not happen)", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "external_id" => "foobar#abc123"
        })

      assert {:discard, [name_last: {"can't be blank", [validation: :required]}, dob: {"can't be blank", [validation: :required]}]} =
               CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end

    test "skips index cases with missing identifier information (even though name_and_id is set - should not happen)", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "name_and_id" => "Glen Livet (foobar#12345)"
        })

      assert {:discard, [name_last: {"can't be blank", [validation: :required]}, dob: {"can't be blank", [validation: :required]}]} =
               CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end

    test "skips index cases with missing identifier information (even though lab result's external_id is set - should not happen)", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen"
        })
        |> with_child(%{
          "accession_number" => "ABC100001",
          "analysis_date" => "2020-05-22",
          "case_name" => " lab_result",
          "case_type" => "lab_result",
          "date_opened" => "2020-06-04T00:00:00.000000Z",
          "doh_mpi_id" => "9999",
          "external_id" => "9999#1234#ABC100001",
          "lab_result" => "positive",
          "laboratory" => "Access DX Laboratory, LLC",
          "owner_id" => @user_id,
          "specimen_collection_date" => "2020-05-22",
          "specimen_source" => "Nasopharyngeal Swab",
          "test_type" => "SARS coronavirus 2 RNA [Presence] in Unspecified s"
        })

      assert {:discard, [name_last: {"can't be blank", [validation: :required]}, dob: {"can't be blank", [validation: :required]}]} =
               CaseImporter.import_case(:create, case: patient_case, county: context.county)
    end
  end

  describe "process - CommCare exclusion filters for cases previously imported" do
    setup context do
      case_id = Ecto.UUID.generate()

      {:ok, person} = Commcare.create_person(%{data: %{}, patient_keys: [], name_first: "Glen", name_last: "Livet", dob: "2000-01-02"})

      {:ok, existing_index_case} = Commcare.create_index_case(%{case_id: case_id, data: %{}, person_id: person.id, county_id: 12})

      [county: context.county, case_id: case_id, existing_index_case: existing_index_case]
    end

    test "updates existing cases to set properties[final_disposition] IN (registered_in_error,duplicate,not_a_case)", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "final_disposition" => "registered_in_error"
        })

      patient_case = Map.put(patient_case, "case_id", context.case_id)

      assert :ok = CaseImporter.import_case(:update, case: patient_case, county: context.county)
      {:ok, index_case} = Commcare.get_index_case(case_id: context.case_id, county_id: context.county.fips)

      index_case.id |> assert_eq(context.existing_index_case.id)

      index_case.data
      |> assert_eq(%{
        "first_name" => "Glen",
        "last_name" => "Livet",
        "dob" => "2000-01-02",
        "final_disposition" => "registered_in_error",
        "case_type" => "patient"
      })

      index_case |> assert_events(["updated_from_commcare"])

      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "final_disposition" => "duplicate"
        })

      patient_case =
        patient_case
        |> Map.put("case_id", context.case_id)
        |> Map.put("date_modified", "2020-06-04T13:43:10.375001Z")

      assert :ok = CaseImporter.import_case(:update, case: patient_case, county: context.county)
      {:ok, index_case} = Commcare.get_index_case(case_id: context.case_id, county_id: context.county.fips)

      index_case.id |> assert_eq(context.existing_index_case.id)

      index_case.data
      |> assert_eq(%{
        "first_name" => "Glen",
        "last_name" => "Livet",
        "dob" => "2000-01-02",
        "final_disposition" => "duplicate",
        "case_type" => "patient"
      })

      index_case |> assert_events(["updated_from_commcare", "updated_from_commcare"])

      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "final_disposition" => "not_a_case"
        })

      patient_case =
        patient_case
        |> Map.put("case_id", context.case_id)
        |> Map.put("date_modified", "2020-06-04T13:43:10.375002Z")

      assert :ok = CaseImporter.import_case(:update, case: patient_case, county: context.county)

      {:ok, index_case} = Commcare.get_index_case(case_id: context.case_id, county_id: context.county.fips)

      index_case.id |> assert_eq(context.existing_index_case.id)

      index_case.data
      |> assert_eq(%{
        "first_name" => "Glen",
        "last_name" => "Livet",
        "dob" => "2000-01-02",
        "final_disposition" => "not_a_case",
        "case_type" => "patient"
      })

      index_case |> assert_events(["updated_from_commcare", "updated_from_commcare", "updated_from_commcare"])
    end

    test "updates existing cases to set properties[stub]=yes", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "stub" => "yes"
        })

      patient_case = Map.put(patient_case, "case_id", context.case_id)

      assert :ok = CaseImporter.import_case(:update, case: patient_case, county: context.county)
      {:ok, index_case} = Commcare.get_index_case(case_id: context.case_id, county_id: context.county.fips)

      index_case.id |> assert_eq(context.existing_index_case.id)

      index_case.data
      |> assert_eq(%{
        "first_name" => "Glen",
        "last_name" => "Livet",
        "dob" => "2000-01-02",
        "stub" => "yes",
        "case_type" => "patient"
      })

      index_case |> assert_events(["updated_from_commcare"])
    end

    test "updates existing cases to set closed=true (at the top-level)", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02"
        })

      patient_case = patient_case |> Map.put("case_id", context.case_id) |> Map.put("closed", true)

      assert :ok = CaseImporter.import_case(:update, case: patient_case, county: context.county)
      {:ok, index_case} = Commcare.get_index_case(case_id: context.case_id, county_id: context.county.fips)

      index_case.id |> assert_eq(context.existing_index_case.id)

      assert index_case.closed
      index_case |> assert_events(["updated_from_commcare"])
    end

    test "updates existing cases to set current_status=closed and patient_type=pui", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "current_status" => "closed",
          "patient_type" => "pui"
        })

      patient_case = Map.put(patient_case, "case_id", context.case_id)

      assert :ok = CaseImporter.import_case(:update, case: patient_case, county: context.county)
      {:ok, index_case} = Commcare.get_index_case(case_id: context.case_id, county_id: context.county.fips)

      index_case.id |> assert_eq(context.existing_index_case.id)

      index_case.data
      |> assert_eq(%{
        "first_name" => "Glen",
        "last_name" => "Livet",
        "dob" => "2000-01-02",
        "current_status" => "closed",
        "patient_type" => "pui",
        "case_type" => "patient"
      })

      index_case |> assert_events(["updated_from_commcare"])
    end

    test "updates existing cases to set transfer_status IN (pending,sent)", context do
      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "transfer_status" => "pending"
        })

      patient_case = Map.put(patient_case, "case_id", context.case_id)

      assert :ok = CaseImporter.import_case(:update, case: patient_case, county: context.county)
      {:ok, index_case} = Commcare.get_index_case(case_id: context.case_id, county_id: context.county.fips)

      index_case.id |> assert_eq(context.existing_index_case.id)

      index_case.data
      |> assert_eq(%{
        "first_name" => "Glen",
        "last_name" => "Livet",
        "dob" => "2000-01-02",
        "transfer_status" => "pending",
        "case_type" => "patient"
      })

      index_case |> assert_events(["updated_from_commcare"])

      {_case_id, patient_case} =
        fixture(%{
          "first_name" => "Glen",
          "last_name" => "Livet",
          "dob" => "2000-01-02",
          "transfer_status" => "sent"
        })

      patient_case =
        patient_case
        |> Map.put("case_id", context.case_id)
        |> Map.put("date_modified", "2020-06-04T13:43:10.375001Z")

      assert :ok = CaseImporter.import_case(:update, case: patient_case, county: context.county)
      {:ok, index_case} = Commcare.get_index_case(case_id: context.case_id, county_id: context.county.fips)

      index_case.id |> assert_eq(context.existing_index_case.id)

      index_case.data
      |> assert_eq(%{
        "first_name" => "Glen",
        "last_name" => "Livet",
        "dob" => "2000-01-02",
        "transfer_status" => "sent",
        "case_type" => "patient"
      })

      index_case |> assert_events(["updated_from_commcare", "updated_from_commcare"])
    end
  end
end
