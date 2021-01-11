defmodule NYSETL.Tasks.BackfillPapertrailVersionsTest do
  use NYSETL.DataCase, async: false

  alias NYSETL.ECLRS
  alias NYSETL.Commcare
  alias NYSETL.Tasks.BackfillPapertrailVersions

  test "it creates a Version record for each existing IndexCase and LabResult" do
    {:ok, _county} = ECLRS.find_or_create_county(111)

    person_attrs = %{"data" => %{"p" => 1}, "patient_keys" => ["123", "456"], "name_first" => "Joe", "name_last" => "Buck", "dob" => "1972-06-29"}

    {:ok, person} =
      %Commcare.Person{}
      |> Commcare.Person.changeset(person_attrs)
      |> Repo.insert()

    person_item_changes =
      Map.merge(person_attrs, %{
        "id" => person.id,
        "inserted_at" => NaiveDateTime.to_iso8601(person.inserted_at),
        "updated_at" => NaiveDateTime.to_iso8601(person.updated_at)
      })

    index_case_attrs = %{"data" => %{"a" => 1}, "person_id" => person.id, "county_id" => 111, "case_id" => "abc123", "tid" => "foo456"}

    {:ok, index_case} =
      %Commcare.IndexCase{}
      |> Commcare.IndexCase.changeset(index_case_attrs)
      |> Repo.insert()

    index_case_changes =
      Map.merge(index_case_attrs, %{
        "id" => index_case.id,
        "inserted_at" => NaiveDateTime.to_iso8601(index_case.inserted_at),
        "updated_at" => NaiveDateTime.to_iso8601(index_case.updated_at)
      })

    lab_result_attrs = %{
      "data" => %{"b" => 2},
      "index_case_id" => index_case.id,
      "case_id" => "lab_result_foobar123",
      "accession_number" => "abc123",
      "tid" => "bar789"
    }

    {:ok, lab_result} =
      %Commcare.LabResult{}
      |> Commcare.LabResult.changeset(lab_result_attrs)
      |> Repo.insert()

    lab_result_changes =
      Map.merge(lab_result_attrs, %{
        "id" => lab_result.id,
        "inserted_at" => NaiveDateTime.to_iso8601(lab_result.inserted_at),
        "updated_at" => NaiveDateTime.to_iso8601(lab_result.updated_at)
      })

    BackfillPapertrailVersions.run()

    PaperTrail.Version |> Repo.count() |> assert_eq(3)

    # TODO: estend assert_eq to allow an exact list of keys we care about
    PaperTrail.get_version(person)
    |> assert_eq(
      %{
        event: "insert",
        item_changes: person_item_changes,
        item_id: person.id,
        item_type: "Person",
        meta: nil,
        origin: "backfill",
        originator_id: nil
      },
      only: ~w{event item_changes item_id item_type meta origin originator_id}a
    )

    PaperTrail.get_version(index_case)
    |> assert_eq(
      %{
        event: "insert",
        item_changes: index_case_changes,
        item_id: index_case.id,
        item_type: "IndexCase",
        meta: nil,
        origin: "backfill",
        originator_id: nil
      },
      only: ~w{event item_changes item_id item_type meta origin originator_id}a
    )

    PaperTrail.get_version(lab_result)
    |> assert_eq(
      %{
        event: "insert",
        item_changes: lab_result_changes,
        item_id: lab_result.id,
        item_type: "LabResult",
        meta: nil,
        origin: "backfill",
        originator_id: nil
      },
      only: ~w{event item_changes item_id item_type meta origin originator_id}a
    )
  end
end
