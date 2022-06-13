defmodule NYSETL.CommcareTest do
  use NYSETL.DataCase, async: true

  alias NYSETL.Commcare
  alias NYSETL.Commcare.County
  alias NYSETL.ECLRS
  alias NYSETL.Test
  alias NYSETL.Test.MessageCollector

  defp set_up_person(_context) do
    {:ok, _county} = ECLRS.find_or_create_county(111)
    {:ok, person} = %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.create_person()
    [person: person]
  end

  defp set_up_index_case(_context) do
    {:ok, _county} = ECLRS.find_or_create_county(111)
    {:ok, person} = %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.create_person()
    {:ok, index_case} = %{data: %{a: 1}, person_id: person.id, county_id: 111} |> Commcare.create_index_case()
    [index_case: index_case]
  end

  defp set_up_lab_result(context) do
    [index_case: index_case] = set_up_index_case(context)

    {:ok, lab_result} =
      %{data: %{b: 2}, index_case_id: index_case.id, accession_number: "abc123"}
      |> Commcare.create_lab_result()

    [lab_result: lab_result]
  end

  describe "create_index_case/1" do
    setup :set_up_person

    test "is {:ok, index_case} when attrs are valid", %{person: person} do
      {:ok, index_case} = %{data: %{a: 1}, person_id: person.id, county_id: 111} |> Commcare.create_index_case()

      index_case
      |> assert_eq(
        %{
          data: %{a: 1},
          person_id: person.id
        },
        only: ~w{data person_id}a
      )
    end

    test "it saves an entry in the PaperTrail Versions table", %{person: person} do
      {:ok, index_case} =
        %{data: %{a: 1}, person_id: person.id, county_id: 111}
        |> Commcare.create_index_case()

      assert PaperTrail.get_version(index_case)
    end

    test "is {:error, changeset} when attempting to create non-unique case_id", %{person: person} do
      {:ok, index_case} = %{data: %{a: 1}, person_id: person.id, county_id: 111} |> Commcare.create_index_case()

      assert {:error, changeset} =
               %{case_id: index_case.case_id, data: %{}, person_id: person.id, county_id: 1111}
               |> Commcare.create_index_case()

      assert "has already been taken" in errors_on(changeset).case_id
    end
  end

  describe "create_index_case/2" do
    setup :set_up_person

    test "it saves an entry in the PaperTrail Versions table and includes meta", %{person: person} do
      meta = %{"some_id" => 123, "some_data" => %{"zzz" => 555}}

      {:ok, index_case} =
        %{data: %{a: 1}, person_id: person.id, county_id: 111}
        |> Commcare.create_index_case(meta)

      PaperTrail.get_version(index_case)
      |> assert_eq(
        %{
          item_id: index_case.id,
          item_type: "IndexCase",
          event: "insert",
          meta: meta
        },
        only: ~w(item_id item_type event meta)a
      )
    end
  end

  describe "create_lab_result/1" do
    setup :set_up_index_case

    test "is {:ok, lab_result} when attrs are valid", %{index_case: index_case} do
      {:ok, lab_result} =
        %{data: %{b: 2}, index_case_id: index_case.id, accession_number: "abc123"}
        |> Commcare.create_lab_result()

      lab_result
      |> assert_eq(
        %{
          data: %{b: 2},
          index_case_id: index_case.id
        },
        only: ~w{data index_case_id}a
      )
    end

    test "it saves an entry in the PaperTrail Versions table", %{index_case: index_case} do
      {:ok, lab_result} =
        %{data: %{b: 2}, index_case_id: index_case.id, accession_number: "abc123"}
        |> Commcare.create_lab_result()

      assert PaperTrail.get_version(lab_result)
    end

    test "is {:error, changeset} when attrs are invalid", %{index_case: index_case} do
      assert {:error, changeset} =
               %{index_case_id: index_case.id, accession_number: "abc123"}
               |> Commcare.create_lab_result()

      assert "can't be blank" in errors_on(changeset).data
    end
  end

  describe "create_lab_result/2" do
    setup :set_up_index_case

    test "it saves an entry in the PaperTrail Versions table and includes meta", %{index_case: index_case} do
      meta = %{"some_id" => 123, "some_data" => %{"zzz" => 555}}

      {:ok, lab_result} =
        %{data: %{b: 2}, index_case_id: index_case.id, accession_number: "abc123"}
        |> Commcare.create_lab_result(meta)

      PaperTrail.get_version(lab_result)
      |> assert_eq(
        %{
          item_id: lab_result.id,
          item_type: "LabResult",
          event: "insert",
          meta: meta
        },
        only: ~w(item_id item_type event meta)a
      )
    end
  end

  describe "create_person" do
    test "is {:ok, patient} when attrs are valid" do
      {:ok, person} = %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.create_person()

      person
      |> assert_eq(
        %{
          data: %{},
          patient_keys: ["123", "456"]
        },
        only: ~w{data patient_keys}a
      )
    end

    test "it saves an entry in the PaperTrail Versions table" do
      {:ok, person} = %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.create_person()

      assert PaperTrail.get_version(person)
    end

    test "is {:error, changeset} when attrs are invalid" do
      assert {:error, changeset} = %{patient_keys: ["123", "456"]} |> Commcare.create_person()

      assert "can't be blank" in errors_on(changeset).data
    end

    test "is {:ok, person} with (name_first, name_last, dob) set, but not patient_keys" do
      {:ok, person} = %{data: %{}, patient_keys: [], name_first: "Joe", name_last: "Testuser", dob: "2020-01-02"} |> Commcare.create_person()

      assert PaperTrail.get_version(person)
    end

    test "is {:error, changeset} when missing (name_first, name_last, dob) and patient_keys" do
      assert {:error, changeset} = %{data: %{}, patient_keys: []} |> Commcare.create_person()

      assert "can't be blank" in errors_on(changeset).name_first
      assert "can't be blank" in errors_on(changeset).name_last
      assert "can't be blank" in errors_on(changeset).dob
    end

    test "is {:error, changeset} when any of (name_first, name_last, dob) are blank strings, and patient_keys is empty" do
      assert {:error, changeset} = %{data: %{}, patient_keys: [], name_first: "", name_last: " ", dob: "  "} |> Commcare.create_person()

      assert "can't be blank" in errors_on(changeset).name_first
      assert "can't be blank" in errors_on(changeset).name_last
      assert "is invalid" in errors_on(changeset).dob
    end
  end

  describe "external_id" do
    test "prepends a person id with P" do
      id = Faker.format("#####") |> String.to_integer()

      %Commcare.Person{id: id}
      |> Commcare.external_id()
      |> assert_eq("P#{id}")
    end
  end

  describe "get_index_cases" do
    test "is {:ok, index_cases} when records can by matched by person and county" do
      {:ok, _county} = ECLRS.find_or_create_county(71)
      {:ok, _county} = ECLRS.find_or_create_county(72)

      %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.Person.changeset() |> Repo.insert!()
      {:ok, person} = Commcare.get_person(patient_key: "456")
      {:ok, _index_case} = %{data: %{dob: "12DEC1998", fips: "71"}, person_id: person.id, county_id: 71} |> Commcare.create_index_case()
      {:ok, _index_case} = %{data: %{dob: "12DEC1998", fips: "72"}, person_id: person.id, county_id: 72} |> Commcare.create_index_case()
      {:ok, [index_case]} = Commcare.get_index_cases(person, county_id: 71)

      index_case
      |> assert_eq(
        %{
          data: %{"dob" => "12DEC1998", "fips" => "71"},
          county_id: 71,
          person_id: person.id
        },
        only: ~w{data county_id person_id}a
      )
    end

    test "is {:ok, index_cases} when a multiple records exist for a person but only one has a lab_result matching the accession_number" do
      {:ok, _county} = ECLRS.find_or_create_county(71)
      {:ok, _county} = ECLRS.find_or_create_county(72)

      %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.Person.changeset() |> Repo.insert!()
      {:ok, person} = Commcare.get_person(patient_key: "456")

      {:ok, index_case_1} =
        %{tid: "first", data: %{dob: "12DEC1998", fips: "71"}, person_id: person.id, county_id: 71} |> Commcare.create_index_case()

      {:ok, _lab_result} = %{data: %{b: 2}, index_case_id: index_case_1.id, accession_number: "abc123"} |> Commcare.create_lab_result()

      {:ok, index_case_2} =
        %{tid: "second", data: %{dob: "12DEC1998", fips: "71"}, person_id: person.id, county_id: 71} |> Commcare.create_index_case()

      {:ok, _lab_result} = %{data: %{b: 2}, index_case_id: index_case_2.id, accession_number: "abc567"} |> Commcare.create_lab_result()

      {:ok, _index_case} = %{data: %{dob: "12DEC1998", fips: "72"}, person_id: person.id, county_id: 72} |> Commcare.create_index_case()
      {:ok, [index_case]} = Commcare.get_index_cases(person, county_id: 71, accession_number: "abc123")

      index_case.tid |> assert_eq("first")
    end

    test "is {:ok, index_cases} when a multiple records exist for a person, and one has more than one lab_result matching the accession_number" do
      {:ok, _county} = ECLRS.find_or_create_county(71)
      {:ok, _county} = ECLRS.find_or_create_county(72)

      %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.Person.changeset() |> Repo.insert!()
      {:ok, person} = Commcare.get_person(patient_key: "456")

      {:ok, index_case_1} =
        %{tid: "first", data: %{dob: "12DEC1998", fips: "71"}, person_id: person.id, county_id: 71} |> Commcare.create_index_case()

      {:ok, _lab_result_1} = %{data: %{b: 2}, index_case_id: index_case_1.id, accession_number: "abc123"} |> Commcare.create_lab_result()
      {:ok, _lab_result_2} = %{data: %{b: 2}, index_case_id: index_case_1.id, accession_number: "abc123"} |> Commcare.create_lab_result()

      {:ok, index_case_2} =
        %{tid: "second", data: %{dob: "12DEC1998", fips: "71"}, person_id: person.id, county_id: 71} |> Commcare.create_index_case()

      {:ok, _lab_result} = %{data: %{b: 2}, index_case_id: index_case_2.id, accession_number: "abc567"} |> Commcare.create_lab_result()

      {:ok, _index_case} = %{data: %{dob: "12DEC1998", fips: "72"}, person_id: person.id, county_id: 72} |> Commcare.create_index_case()
      {:ok, [index_case]} = Commcare.get_index_cases(person, county_id: 71, accession_number: "abc123")

      index_case.tid |> assert_eq("first")
    end

    test "is {:ok, index_cases} when record exists in the county, but no labs match accession_number" do
      {:ok, _county} = ECLRS.find_or_create_county(71)
      {:ok, _county} = ECLRS.find_or_create_county(72)

      %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.Person.changeset() |> Repo.insert!()
      {:ok, person} = Commcare.get_person(patient_key: "456")

      {:ok, index_case} = %{tid: "first", data: %{dob: "12DEC1998", fips: "71"}, person_id: person.id, county_id: 71} |> Commcare.create_index_case()

      {:ok, _lab_result} = %{data: %{b: 2}, index_case_id: index_case.id, accession_number: "abc123"} |> Commcare.create_lab_result()

      {:ok, _index_case} = %{data: %{dob: "12DEC1998", fips: "72"}, person_id: person.id, county_id: 72} |> Commcare.create_index_case()
      {:ok, [index_case]} = Commcare.get_index_cases(person, county_id: 71, accession_number: "abc567")

      index_case.tid |> assert_eq("first")
    end

    test "is {:error, :not_found} when no index case matches data keys" do
      {:ok, _county} = ECLRS.find_or_create_county(71)
      %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.Person.changeset() |> Repo.insert!()
      {:ok, person} = Commcare.get_person(patient_key: "456")
      {:ok, _index_case} = %{data: %{dob: "12DEC1998", fips: "72"}, person_id: person.id, county_id: 71} |> Commcare.create_index_case()
      assert {:error, :not_found} = Commcare.get_index_cases(person, county_id: 72)
    end

    test "is {:error, :muliple_index_cases} when multiple index cases may match the query" do
      {:ok, _county} = ECLRS.find_or_create_county(71)
      {:ok, _county} = ECLRS.find_or_create_county(72)

      %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.Person.changeset() |> Repo.insert!()
      {:ok, person} = Commcare.get_person(patient_key: "456")

      {:ok, index_case_1} = %{tid: "first", data: %{}, person_id: person.id, county_id: 71} |> Commcare.create_index_case()
      {:ok, _lab_result} = %{data: %{b: 2}, index_case_id: index_case_1.id, accession_number: "abc123"} |> Commcare.create_lab_result()

      {:ok, index_case_2} = %{tid: "second", data: %{}, person_id: person.id, county_id: 71} |> Commcare.create_index_case()
      {:ok, _lab_result} = %{data: %{b: 2}, index_case_id: index_case_2.id, accession_number: "abc567"} |> Commcare.create_lab_result()

      {:ok, _index_case} = %{data: %{dob: "12DEC1998", fips: "72"}, person_id: person.id, county_id: 72} |> Commcare.create_index_case()

      assert {:ok, index_cases} = Commcare.get_index_cases(person, county_id: 71)

      index_cases
      |> Euclid.Enum.tids()
      |> assert_eq(~w(first second))
    end
  end

  describe "get_index_case" do
    test "is {:ok, index_case} when a record can be matched by case_id and county" do
      {:ok, _county} = ECLRS.find_or_create_county(71)
      {:ok, _county} = ECLRS.find_or_create_county(72)

      case_id = Ecto.UUID.generate()

      %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.Person.changeset() |> Repo.insert!()
      {:ok, person} = Commcare.get_person(patient_key: "456")
      {:ok, index_case_1} = %{case_id: case_id, data: %{}, person_id: person.id, county_id: 71} |> Commcare.create_index_case()
      {:ok, index_case} = Commcare.get_index_case(case_id: case_id, county_id: 71)

      index_case.id |> assert_eq(index_case_1.id)
    end
  end

  describe "get_lab_results/2" do
    test "returns an :ok tuple with a list of lab_results, when one or more lab_result can be found by index_case_id and accession_number" do
      {:ok, _county} = ECLRS.find_or_create_county(111)
      {:ok, person} = %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.create_person()
      {:ok, index_case} = %{data: %{a: 1}, person_id: person.id, county_id: 111} |> Commcare.create_index_case()

      {:ok, lab_result} =
        %{data: %{b: 2}, index_case_id: index_case.id, accession_number: "lab_result_accession_number"} |> Commcare.create_lab_result()

      {:ok, [fetched_lab_result]} = Commcare.get_lab_results(index_case, accession_number: "lab_result_accession_number")

      assert fetched_lab_result.id == lab_result.id
    end

    test "is {:error, :not_found} when no lab_result for the index_case matches the accession_number" do
      {:ok, _county} = ECLRS.find_or_create_county(111)
      {:ok, person} = %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.create_person()
      {:ok, index_case} = %{data: %{a: 1}, person_id: person.id, county_id: 111} |> Commcare.create_index_case()
      %{data: %{b: 2}, index_case_id: index_case.id, accession_number: "lab_result_accession_number"} |> Commcare.create_lab_result()

      assert {:error, :not_found} = Commcare.get_lab_results(index_case, accession_number: "unknown_accession_number")
    end
  end

  describe "get_lab_results/1" do
    test "returns a list of lab_results, ordered by inserted_at ASC, when lab_results can be found by index_case_id" do
      {:ok, _county} = ECLRS.find_or_create_county(111)
      {:ok, person} = %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.create_person()
      {:ok, index_case} = %{data: %{a: 1}, person_id: person.id, county_id: 111} |> Commcare.create_index_case()
      {:ok, _} = Test.Factory.lab_result(index_case, tid: "older_lab_result", inserted_at: ~U[2020-05-29 03:59:00Z]) |> Commcare.create_lab_result()
      {:ok, _} = Test.Factory.lab_result(index_case, tid: "newer_lab_result", inserted_at: ~U[2020-05-30 03:59:00Z]) |> Commcare.create_lab_result()

      Commcare.get_lab_results(index_case)
      |> Enum.map(& &1.tid)
      |> assert_eq(["older_lab_result", "newer_lab_result"])
    end

    test "returns empty list when there are no lab results for that index case" do
      {:ok, _county} = ECLRS.find_or_create_county(111)
      {:ok, person} = %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.create_person()
      {:ok, index_case} = %{data: %{a: 1}, person_id: person.id, county_id: 111} |> Commcare.create_index_case()
      {:ok, other_index_case} = %{data: %{a: 1}, person_id: person.id, county_id: 111} |> Commcare.create_index_case()
      {:ok, _} = Test.Factory.lab_result(other_index_case, tid: "other_index_case_lab_result") |> Commcare.create_lab_result()

      assert [] = Commcare.get_lab_results(index_case)
    end
  end

  describe "get_unprocessed_index_cases" do
    @update_events ["index_case_updated", "index_case_created", "lab_result_created", "lab_result_updated", "send_to_commcare_enqueued"]
    @send_events ["send_to_commcare_succeeded", "send_to_commcare_rerouted", "send_to_commcare_discarded"]
    @commcare_events ["retrieved_from_commcare", "updated_from_commcare"]

    def create_index_case_with_events(events) do
      {:ok, _county} = ECLRS.find_or_create_county(71)

      person = %{data: %{}, patient_keys: ["123"]} |> Commcare.Person.changeset() |> Repo.insert!()
      {:ok, index_case} = %{data: %{}, person_id: person.id, county_id: 71} |> Commcare.create_index_case()

      Enum.each(events, &Commcare.save_event(index_case, &1))

      index_case
    end

    def assert_unprocessed_index_case(index_case) do
      index_case_id = index_case.id
      assert [%{id: ^index_case_id}] = Commcare.get_unprocessed_index_cases() |> Repo.all()
    end

    def assert_no_unprocessed_index_cases do
      assert [] == Commcare.get_unprocessed_index_cases() |> Repo.all()
    end

    for update_event <- @update_events do
      @tag update_event: update_event
      test "include cases with #{update_event} that are never sent", %{update_event: update_event} do
        [update_event]
        |> create_index_case_with_events()
        |> assert_unprocessed_index_case()
      end
    end

    for update_event <- @update_events, send_event <- @send_events do
      @tag update_event: update_event, send_event: send_event
      test "include cases with #{send_event} followed by #{update_event}", %{update_event: update_event, send_event: send_event} do
        [send_event, update_event]
        |> create_index_case_with_events()
        |> assert_unprocessed_index_case()
      end
    end

    for update_event <- @update_events, send_event <- @send_events do
      @tag update_event: update_event, send_event: send_event
      test "exclude cases with #{update_event} followed by #{send_event}", %{update_event: update_event, send_event: send_event} do
        create_index_case_with_events([update_event, send_event])
        assert_no_unprocessed_index_cases()
      end
    end

    for update_event <- @update_events, commcare_event <- @commcare_events do
      @tag update_event: update_event, commcare_event: commcare_event
      test "include cases with #{commcare_event} followed by #{update_event}", %{update_event: update_event, commcare_event: commcare_event} do
        [commcare_event, update_event]
        |> create_index_case_with_events()
        |> assert_unprocessed_index_case()
      end
    end

    for commcare_event <- @commcare_events do
      @tag commcare_event: commcare_event
      test "exclude cases with #{commcare_event} and no update event", %{commcare_event: commcare_event} do
        create_index_case_with_events([commcare_event])
        assert_no_unprocessed_index_cases()
      end
    end
  end

  test "get_index_cases_with_invalid_all_activity_complete_date" do
    {:ok, midsomer} = County.get(name: "midsomer")
    {:ok, midsomer_county} = ECLRS.find_or_create_county(midsomer.fips)

    {:ok, person1} = Commcare.create_person(%{data: %{}, patient_keys: ["1"], name_first: nil, name_last: nil})

    {:ok, _} =
      Commcare.create_index_case(%{
        case_id: "invalid-date",
        data: %{"all_activity_complete_date" => "date(today())"},
        person_id: person1.id,
        county_id: midsomer_county.id
      })

    {:ok, person2} = Commcare.create_person(%{data: %{}, patient_keys: ["2"], name_first: nil, name_last: nil})

    {:ok, _} =
      Commcare.create_index_case(%{
        case_id: "ok-date",
        data: %{"all_activity_complete_date" => "2022-05-04"},
        person_id: person2.id,
        county_id: midsomer_county.id
      })

    {:ok, person3} = Commcare.create_person(%{data: %{}, patient_keys: ["3"], name_first: nil, name_last: nil})

    {:ok, _} =
      Commcare.create_index_case(%{
        case_id: "no-date",
        data: %{"all_activity_complete_date" => ""},
        person_id: person3.id,
        county_id: midsomer_county.id
      })

    assert [%{case_id: "invalid-date"}] = Commcare.get_index_cases_with_invalid_all_activity_complete_date() |> Repo.all()
  end

  test "get_index_cases_without_commcare_date_modified" do
    {:ok, midsomer} = County.get(name: "midsomer")
    {:ok, midsomer_county} = ECLRS.find_or_create_county(midsomer.fips)

    {:ok, person1} = Commcare.create_person(%{data: %{}, patient_keys: ["1"], name_first: nil, name_last: nil})

    {:ok, _} =
      Commcare.create_index_case(%{
        case_id: "missing-date-modified",
        person_id: person1.id,
        county_id: midsomer_county.id,
        data: %{}
      })

    {:ok, person2} = Commcare.create_person(%{data: %{}, patient_keys: ["2"], name_first: nil, name_last: nil})

    {:ok, _} =
      Commcare.create_index_case(%{
        case_id: "ok-date-modified",
        person_id: person2.id,
        county_id: midsomer_county.id,
        data: %{},
        commcare_date_modified: DateTime.utc_now()
      })

    assert [%{case_id: "missing-date-modified"}] = Commcare.get_index_cases_without_commcare_date_modified() |> Repo.all()
  end

  describe "get_person" do
    test "is {:ok, person} when a person can be found by patient_key" do
      %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.Person.changeset() |> Repo.insert!()
      {:ok, person} = Commcare.get_person(patient_key: "456")

      person
      |> assert_eq(
        %{
          data: %{},
          patient_keys: ["123", "456"]
        },
        only: ~w{data patient_keys}a
      )
    end

    test "is {:ok, person} when a person can be found by dob and name" do
      %{data: %{}, patient_keys: ["123", "456"], dob: ~D[1990-03-12], name_last: "Smith", name_first: "Sam"}
      |> Commcare.Person.changeset()
      |> Repo.insert!()

      {:ok, person} = Commcare.get_person(dob: ~D[1990-03-12], name_first: "Sam", name_last: "Smith")

      person
      |> assert_eq(
        %{
          data: %{},
          dob: ~D[1990-03-12],
          name_first: "Sam",
          name_last: "Smith",
          patient_keys: ["123", "456"]
        },
        only: ~w{data dob name_first name_last patient_keys}a
      )
    end

    test "is {:ok, person} when dob and full name match exactly" do
      %{data: %{}, patient_keys: ["123", "456"], dob: ~D[1990-03-15], name_last: "Smith Smath", name_first: "Smyth"}
      |> Commcare.Person.changeset()
      |> Repo.insert!()

      %{data: %{}, patient_keys: ["789"], dob: ~D[1990-03-15], name_last: "Smurth", name_first: "Smyth"}
      |> Commcare.Person.changeset()
      |> Repo.insert!()

      {:ok, person} = Commcare.get_person(dob: ~D[1990-03-15], full_name: "Smyth Smith Smath")

      person
      |> assert_eq(
        %{
          data: %{},
          dob: ~D[1990-03-15],
          name_first: "Smyth",
          name_last: "Smith Smath",
          patient_keys: ["123", "456"]
        },
        only: ~w{data dob name_first name_last patient_keys}a
      )
    end

    test "is {:ok, person} when dob matches and (name_last & name_first) match full name" do
      %{data: %{}, patient_keys: ["1"], dob: ~D[1990-03-15], name_last: "SMITH SMATH", name_first: "SMYTH"}
      |> Commcare.Person.changeset()
      |> Repo.insert!()

      %{data: %{}, patient_keys: ["2"], dob: ~D[1990-03-15], name_last: "SMURTH", name_first: "SMYTH"}
      |> Commcare.Person.changeset()
      |> Repo.insert!()

      %{data: %{}, patient_keys: ["3"], dob: ~D[1990-03-14], name_last: "SMITH SMATH", name_first: "SMYTH"}
      |> Commcare.Person.changeset()
      |> Repo.insert!()

      %{data: %{}, patient_keys: ["4"], dob: ~D[2008-01-02], name_first: "JASON", name_last: "PARKER KLINE"}
      |> Commcare.create_person()

      {:ok, person} = Commcare.get_person(dob: ~D[1990-03-15], full_name: "Smyth Smeth smith Smath")

      person
      |> assert_eq(
        %{
          data: %{},
          dob: ~D[1990-03-15],
          name_first: "SMYTH",
          name_last: "SMITH SMATH",
          patient_keys: ["1"]
        },
        only: ~w{data dob name_first name_last patient_keys}a
      )

      Commcare.get_person(dob: ~D[1990-03-15], full_name: "smurth")
      |> assert_eq({:error, :not_found})

      Commcare.get_person(dob: ~D[1990-03-15], full_name: "Smeth Smith Smath")
      |> assert_eq({:error, :not_found})

      Commcare.get_person(dob: ~D[1990-03-15], full_name: "Smyth Smith")
      |> assert_eq({:error, :not_found})

      Commcare.get_person(dob: ~D[1990-03-15], full_name: "smurth smyth")
      |> assert_ok()

      Commcare.get_person(dob: ~D[2008-01-02], full_name: "jason parker kline")
      |> assert_ok()
    end

    test "is {:error, :not_found} when a patient with patient_key does not exist" do
      %{data: %{}, patient_keys: ["123"]} |> Commcare.Person.changeset() |> Repo.insert!()
      assert {:error, :not_found} = Commcare.get_person(patient_key: "456")
    end

    test "is {:ok, person} when there is a matching case id" do
      person = %{data: %{}, patient_keys: ["123"]} |> Commcare.Person.changeset() |> Repo.insert!()

      {:ok, _county} = ECLRS.find_or_create_county(111)

      {:ok, index_case} =
        %{data: %{a: 1}, person_id: person.id, county_id: 111}
        |> Commcare.create_index_case()

      assert {:ok, ^person} = Commcare.get_person(case_id: index_case.case_id)
    end

    test "is {:error, :not_found} when there is no matching case id" do
      assert {:error, :not_found} = Commcare.get_person(case_id: "does-not-exist")
    end

    test "doesn't crash when a person in the DB has a last name that looks like a function" do
      %{data: %{}, patient_keys: ["123", "456"], dob: ~D[1990-03-15], name_last: "Smith(Smath)", name_first: "Smyth"}
      |> Commcare.Person.changeset()
      |> Repo.insert!()

      Commcare.get_person(dob: ~D[1990-03-15], full_name: "Different Person")
      |> assert_eq({:error, :not_found})
    end
  end

  describe "update_person" do
    setup do
      start_supervised!(MessageCollector)
      :ok
    end

    test "serializes access to a single person" do
      # make two different structs so resource lock is only on id, not entire struct
      {:ok, person_v1} = Commcare.create_person(%{name_first: "Person", name_last: "V1", dob: ~D[2021-08-03], patient_keys: [], data: %{}})
      person_v2 = %Commcare.Person{id: person_v1.id, name_first: "Person", name_last: "V2"}

      v1_update =
        Task.async(fn ->
          Commcare.update_person(person_v1, fn ->
            Process.sleep(5)
            MessageCollector.add(:person_v1)
          end)
        end)

      v2_update =
        Task.async(fn ->
          Commcare.update_person(person_v2, fn ->
            MessageCollector.add(:person_v2)
          end)
        end)

      Task.await(v1_update)
      Task.await(v2_update)

      assert MessageCollector.messages() == [:person_v1, :person_v2]
    end

    test "parallelizes access to multiple people" do
      {:ok, person_1} = Commcare.create_person(%{name_first: "Will", name_last: "Smith", dob: ~D[1968-09-25], patient_keys: [], data: %{}})
      {:ok, person_2} = Commcare.create_person(%{name_first: "Chris", name_last: "Rock", dob: ~D[1965-02-07], patient_keys: [], data: %{}})

      person_1_update =
        Task.async(fn ->
          Commcare.update_person(person_1, fn ->
            Process.sleep(5)
            MessageCollector.add(:person_1)
          end)
        end)

      person_2_update =
        Task.async(fn ->
          Commcare.update_person(person_2, fn ->
            MessageCollector.add(:person_2)
          end)
        end)

      Task.await(person_1_update)
      Task.await(person_2_update)

      assert MessageCollector.messages() == [:person_2, :person_1]
    end

    test "bubbles up errors" do
      {:ok, person_1} = Commcare.create_person(%{name_first: "Notwill", name_last: "Smith", dob: ~D[1968-09-25], patient_keys: [], data: %{}})

      assert_raise RuntimeError, "foo", fn ->
        Commcare.update_person(person_1, fn -> raise "foo" end)
      end
    end
  end

  describe "save_event" do
    setup :set_up_index_case

    test "associates an Event with an IndexCase", %{index_case: index_case} do
      {:ok, event} = Commcare.save_event(index_case, "i-did-it")

      assert event.type == "i-did-it"

      [loaded_event] =
        index_case
        |> Repo.preload(:events)
        |> Map.get(:events)

      assert_eq(loaded_event, event)
    end

    test "associates an Event along with Event data with an IndexCase", %{index_case: index_case} do
      stash = Faker.Lorem.sentence()
      data = %{"a" => 1}

      {:ok, event} = Commcare.save_event(index_case, type: "i-did-it", data: data, stash: stash)

      assert event.type == "i-did-it"
      assert_eq(event.data, data)
      assert event.stash == stash

      [loaded_event] =
        index_case
        |> Repo.preload(:events)
        |> Map.get(:events)

      assert_eq(loaded_event, event)
    end
  end

  describe "update_index_case/2" do
    setup :set_up_index_case

    test "is {:ok, index_case} when attrs are valid", %{index_case: index_case} do
      {:ok, updated_index_case} = index_case |> Commcare.update_index_case(%{data: %{b: 1}})

      updated_index_case
      |> assert_eq(%{data: %{b: 1}}, only: ~w{data}a)
    end

    test "it saves an entry in the PaperTrail Versions table", %{index_case: index_case} do
      {:ok, index_case} = Commcare.update_index_case(index_case, %{data: %{b: 1}})

      PaperTrail.get_version(index_case)
      |> assert_eq(%{item_id: index_case.id, item_type: "IndexCase", event: "update"}, only: ~w(item_id item_type event)a)
    end

    test "it does not save a PaperTrail version when there is no change", %{index_case: index_case} do
      before_update_version = PaperTrail.get_version(index_case)
      {:ok, index_case} = Commcare.update_index_case(index_case, %{data: index_case.data})

      PaperTrail.get_version(index_case)
      |> assert_eq(before_update_version)
    end

    test "is {:error, changeset} when attempting to update a index_case with bad data", %{index_case: index_case} do
      assert {:error, changeset} = Commcare.update_index_case(index_case, %{data: nil})

      assert "can't be blank" in errors_on(changeset).data
    end
  end

  describe "update_index_case/3" do
    setup :set_up_index_case

    test "it saves an entry in the PaperTrail Versions table and includes meta", %{index_case: index_case} do
      meta = %{"some_id" => 123, "some_data" => %{"zzz" => 555}}

      {:ok, index_case} = Commcare.update_index_case(index_case, %{data: %{b: 1}}, meta)

      PaperTrail.get_version(index_case)
      |> assert_eq(
        %{
          item_id: index_case.id,
          item_type: "IndexCase",
          event: "update",
          meta: meta
        },
        only: ~w(item_id item_type event meta)a
      )
    end
  end

  describe "update_index_case_from_commcare_data" do
    setup do
      case_id = "case-id-abcd1234"
      {:ok, county} = ECLRS.find_or_create_county(1111)
      {:ok, person} = %{data: %{}, patient_keys: ["123"]} |> Test.Factory.person() |> Commcare.create_person()

      {:ok, index_case} =
        %{
          "case_id" => case_id,
          "data" => %{
            "property1" => "original-value-1",
            "property2" => "original-value-2",
            "property4" => "original-value-4",
            "property5" => "original-value-5"
          },
          "person_id" => person.id,
          "county_id" => county.id
        }
        |> Commcare.create_index_case()

      [index_case: index_case]
    end

    test "merges the provided properties into index case's data, and saves the index case", %{index_case: index_case} do
      commcare_case_properties = %{
        "property1" => "updated-value-1",
        "property3" => "inserted-value-3",
        "property4" => nil,
        "property5" => ""
      }

      {:ok, updated_index_case} = Commcare.update_index_case_from_commcare_data(index_case, %{"properties" => commcare_case_properties})

      assert updated_index_case.data == %{
               "property1" => "updated-value-1",
               "property2" => "original-value-2",
               "property3" => "inserted-value-3",
               "property4" => "original-value-4",
               "property5" => "original-value-5"
             }
    end

    test "saves a PaperTrail version, and includes the full data fetched from CommCare (before the merge)", %{index_case: index_case} do
      commcare_case_properties = %{
        "some" => "values"
      }

      {:ok, updated_index_case} = Commcare.update_index_case_from_commcare_data(index_case, %{"properties" => commcare_case_properties})

      %{meta: %{"fetched_from_commcare" => fetched_from_commcare}} = PaperTrail.get_version(updated_index_case)

      fetched_from_commcare |> assert_eq(commcare_case_properties)
    end
  end

  describe "update_lab_result/2" do
    setup :set_up_lab_result

    test "is {:ok, lab_result} when attrs are valid", %{lab_result: lab_result} do
      {:ok, updated_lab_result} = lab_result |> Commcare.update_lab_result(%{data: %{b: 1}})

      updated_lab_result
      |> assert_eq(%{data: %{b: 1}}, only: ~w{data}a)
    end

    test "it saves an entry in the PaperTrail Versions table", %{lab_result: lab_result} do
      {:ok, lab_result} = Commcare.update_lab_result(lab_result, %{data: %{b: 1}})

      PaperTrail.get_version(lab_result)
      |> assert_eq(%{item_id: lab_result.id, item_type: "LabResult", event: "update"}, only: ~w(item_id item_type event)a)
    end

    test "is {:error, changeset} when attempting to update a lab result with bad data", %{lab_result: lab_result} do
      assert {:error, changeset} = Commcare.update_lab_result(lab_result, %{data: nil})

      assert "can't be blank" in errors_on(changeset).data
    end
  end

  describe "update_lab_result/3" do
    setup :set_up_lab_result

    test "it saves an entry in the PaperTrail Versions table and includes meta", %{lab_result: lab_result} do
      meta = %{"some_id" => 123, "some_data" => %{"zzz" => 555}}

      {:ok, lab_result} = Commcare.update_lab_result(lab_result, %{data: %{b: 1}}, meta)

      PaperTrail.get_version(lab_result)
      |> assert_eq(
        %{
          item_id: lab_result.id,
          item_type: "LabResult",
          event: "update",
          meta: meta
        },
        only: ~w(item_id item_type event meta)a
      )
    end
  end
end
