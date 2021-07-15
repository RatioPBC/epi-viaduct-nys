defmodule NYSETL.Engines.E4.DataTest do
  use NYSETL.DataCase, async: true

  alias NYSETL.Commcare
  alias NYSETL.Engines.E4.Data
  alias NYSETL.ECLRS

  setup do
    {:ok, _county} = ECLRS.find_or_create_county(111)
    {:ok, person} = %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.create_person()
    [person: person]
  end

  describe "from_index_case" do
    """
    returns a map representing the inputs when index_case, lab_results, and county_location_id are present,
    and omits lab_result_notes and most_recent_lab_result_note fields from data
    """
    |> test context do
      {:ok, index_case} =
        %{data: %{"full_name" => "index-case-full-name"}, person_id: context.person.id, county_id: 111, case_id: "index-case-id"}
        |> Commcare.create_index_case()

      {:ok, _lab_result} =
        %{
          data: %{
            "a" => 1,
            "created_manually" => "yes",
            "lab_result_notes" => "important note entered by a case worker",
            "most_recent_lab_result_note" => "important note entered by a case worker"
          },
          case_id: "lab-result-case-id",
          index_case_id: index_case.id,
          accession_number: "lab_result_accession_number"
        }
        |> Commcare.create_lab_result()

      now = DateTime.utc_now()
      now_as_string = now |> Extra.DateTime.to_iso8601(:rounded)
      today_as_string = now |> DateTime.to_date() |> Date.to_iso8601()

      Data.from_index_case(index_case, "county-location-id", now)
      |> assert_eq(%{
        index_case: %{
          case_id: "index-case-id",
          case_type: "patient",
          case_name: "index-case-full-name",
          date_modified: now_as_string,
          owner_id: "county-location-id",
          data: %{
            "full_name" => "index-case-full-name",
            "owner_id" => "county-location-id",
            "new_lab_result_specimen_collection_date" => today_as_string,
            "new_lab_result_received_date" => today_as_string,
            "new_lab_result_received" => "yes"
          }
        },
        lab_results: [
          %{
            case_id: "lab-result-case-id",
            parent_case_id: "index-case-id",
            owner_id: "-",
            data: %{
              "a" => 1,
              "accession_number" => "lab_result_accession_number",
              "owner_id" => "-"
            }
          }
        ]
      })
    end

    test "it replaces the owner_id inside the data map with the passed in location_id", context do
      {:ok, index_case} =
        %{
          data: %{"full_name" => "index-case-full-name", "owner_id" => "original-location-id"},
          person_id: context.person.id,
          county_id: 111,
          case_id: "index-case-id"
        }
        |> Commcare.create_index_case()

      {:ok, _lab_result} = create_lab_result(index_case.id, %{})

      %{index_case: %{data: %{"owner_id" => owner_id}}} = Data.from_index_case(index_case, "county-location-id", DateTime.utc_now())

      assert_eq(owner_id, "county-location-id")
    end

    test "does not assign cases to anybody", context do
      bad_keys = ~w{
        assigned_to_primary_checkin_case_id
        assigned_to_primary_name
        assigned_to_primary_username
        assigned_to_temp_checkin_case_id
        assigned_to_temp_name
        assigned_to_temp_username
      }

      {:ok, index_case} =
        %{
          data: Map.new(["this_stays" | bad_keys], fn k -> {k, k} end),
          person_id: context.person.id,
          county_id: 111,
          case_id: "index-case-id"
        }
        |> Commcare.create_index_case()

      {:ok, _lab_result} = create_lab_result(index_case.id, %{})

      %{index_case: %{data: data}} = Data.from_index_case(index_case, "county-location-id", DateTime.utc_now())

      assert %{"this_stays" => "this_stays"} = data
      assert_eq(bad_keys -- Map.keys(data), bad_keys)
    end

    test "it updates new_lab_result_specimen_collection_date to be the latest collection_date among the case's lab results", context do
      {:ok, index_case} =
        %{
          data: %{"full_name" => "index-case-full-name", "new_lab_result_specimen_collection_date" => ~U[2020-09-30 03:59:00Z]},
          person_id: context.person.id,
          county_id: 111,
          case_id: "index-case-id"
        }
        |> Commcare.create_index_case()

      # start with the case where there is no lab result that has a specimen_collection_date
      {:ok, _lab_result} = create_lab_result(index_case.id, %{})

      %{
        index_case: %{
          data: %{
            "new_lab_result_specimen_collection_date" => collection_date,
            "new_lab_result_received_date" => received_date
          }
        }
      } = Data.from_index_case(index_case, "county-location-id", DateTime.utc_now())

      assert collection_date == index_case.inserted_at |> NaiveDateTime.to_date() |> Date.to_iso8601()
      assert received_date == index_case.inserted_at |> NaiveDateTime.to_date() |> Date.to_iso8601()

      # then add lab results that have specimen_collection_dates
      {:ok, _lab_result} = create_lab_result(index_case.id, %{"specimen_collection_date" => "2020-09-30"})
      {:ok, lab_result} = create_lab_result(index_case.id, %{"specimen_collection_date" => "2020-10-05"})

      %{
        index_case: %{
          data: %{
            "new_lab_result_specimen_collection_date" => collection_date,
            "new_lab_result_received_date" => received_date
          }
        }
      } = Data.from_index_case(index_case, "county-location-id", DateTime.utc_now())

      assert_eq(collection_date, "2020-10-05")
      assert_eq(received_date, lab_result.inserted_at |> NaiveDateTime.to_date() |> Date.to_iso8601())
    end

    test "it updates new_lab_result_received to yes", context do
      {:ok, index_case} =
        %{
          data: %{"full_name" => "index-case-full-name", "new_lab_result_received" => "no"},
          person_id: context.person.id,
          county_id: 111,
          case_id: "index-case-id"
        }
        |> Commcare.create_index_case()

      result = Data.from_index_case(index_case, "county-location-id", DateTime.utc_now())
      assert result.index_case.data["new_lab_result_received"] == "yes"
    end
  end

  describe "new_lab_result_received_date" do
    test "it picks the latest insertion timestamp among the case's lab results" do
      # [, ~N[2020-07-14 21:40:52], ~N[2020-07-14 21:40:52], ]
      lab1 = %NYSETL.Commcare.LabResult{inserted_at: ~N[2020-07-14 21:40:52]}
      lab2 = %NYSETL.Commcare.LabResult{inserted_at: ~N[2020-12-01 16:43:42]}
      lab3 = %NYSETL.Commcare.LabResult{inserted_at: ~N[2020-07-14 21:40:52]}

      Data.new_lab_result_received_date(:no_index_case, [lab1, lab2, lab3])
      |> assert_eq("2020-12-01")
    end
  end

  defp create_lab_result(index_case_id, lab_result_data) do
    %{
      data: lab_result_data,
      index_case_id: index_case_id,
      accession_number: "accession_number"
    }
    |> Commcare.create_lab_result()
  end
end
