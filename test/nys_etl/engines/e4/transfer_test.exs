defmodule NYSETL.Engines.E4.TransferTest do
  use NYSETL.DataCase

  alias NYSETL.Commcare
  alias NYSETL.ECLRS
  alias NYSETL.Extra
  alias NYSETL.Engines.E4.PatientCaseData
  alias NYSETL.Engines.E4.Transfer
  alias NYSETL.Test

  ExUnit.Case.register_attribute(__MODULE__, :child_case_data)

  describe "find_or_create_transferred_index_case_and_lab_results" do
    setup context do
      {:ok, source_county} = ECLRS.find_or_create_county(Test.Fixtures.test_county_1_fips())
      {:ok, destination_county} = ECLRS.find_or_create_county(Test.Fixtures.test_county_2_fips())
      {:ok, person} = %{data: %{}, patient_keys: ["123"]} |> Test.Factory.person() |> Commcare.create_person()

      {:ok, index_case} =
        %{data: %{"thing1" => "value-from-eclrs-1", "thing2" => "value-from-eclrs-2"}, person_id: person.id, county_id: source_county.id}
        |> Commcare.create_index_case()

      {:ok, source_county_lab_result_1} =
        %{data: %{tid: "in_commcare_1"}, index_case_id: index_case.id, accession_number: "in_commcare_1_accession_number"}
        |> Commcare.create_lab_result()

      {:ok, _} =
        %{data: %{tid: "in_commcare_2"}, index_case_id: index_case.id, accession_number: "in_commcare_2_accession_number"}
        |> Commcare.create_lab_result()

      {:ok, _} =
        %{data: %{tid: "not_in_commcare"}, index_case_id: index_case.id, accession_number: "not_in_commcare_accession_number"}
        |> Commcare.create_lab_result()

      destination_case_data =
        PatientCaseData.new(%{
          "case_id" => "destination-case-id",
          "properties" => %{
            "thing1" => "value-from-commcare-1",
            "thing3" => "value-from-commcare-3"
          },
          "child_cases" => context.registered.child_case_data
        })

      [
        source_index_case: index_case,
        source_county_lab_result_1: source_county_lab_result_1,
        destination_case_data: destination_case_data,
        destination_county: destination_county,
        person: person
      ]
    end

    @child_case_data nil
    test "creates a new index case from an existing index case, new commcare data, and a new county id", context do
      {:ok, new_index_case, :created} =
        Transfer.find_or_create_transferred_index_case_and_lab_results(
          context.source_index_case,
          context.destination_case_data,
          context.destination_county.id
        )

      assert new_index_case.case_id == "destination-case-id"
      assert new_index_case.county_id == context.destination_county.id
      assert new_index_case.person_id == context.person.id

      assert new_index_case.data == %{
               "thing1" => "value-from-commcare-1",
               "thing2" => "value-from-eclrs-2",
               "thing3" => "value-from-commcare-3"
             }
    end

    @child_case_data %{
      "destination-lab-result-1-case-id" => %{
        "case_id" => "destination-lab-result-1-case-id",
        "case_type" => "lab_result",
        "properties" => %{
          "accession_number" => "in_commcare_1_accession_number",
          "lab_result_notes" => "important note 1"
        }
      },
      "destination-lab-result-2-case-id" => %{
        "case_id" => "destination-lab-result-2-case-id",
        "case_type" => "lab_result",
        "properties" => %{
          "accession_number" => "in_commcare_2_accession_number",
          "lab_result_notes" => "important note 2"
        }
      },
      "1234" => %{
        "case_id" => "123",
        "case_type" => "not_a_lab_result"
      }
    }
    test "creates lab results for each existing lab result plus new ones from commcare", context do
      {:ok, new_index_case, :created} =
        Transfer.find_or_create_transferred_index_case_and_lab_results(
          context.source_index_case,
          context.destination_case_data,
          context.destination_county.id
        )

      new_index_case
      |> Commcare.get_lab_results()
      |> Enum.map(&Map.take(&1, [:case_id, :index_case_id, :accession_number, :data]))
      |> Enum.map(fn map -> if map.case_id =~ Extra.Regex.uuid(), do: Map.put(map, :case_id, "**generated-uuid**"), else: map end)
      |> assert_eq([
        %{
          case_id: "destination-lab-result-1-case-id",
          index_case_id: new_index_case.id,
          accession_number: "in_commcare_1_accession_number",
          data: %{"tid" => "in_commcare_1"}
        },
        %{
          case_id: "destination-lab-result-2-case-id",
          index_case_id: new_index_case.id,
          accession_number: "in_commcare_2_accession_number",
          data: %{"tid" => "in_commcare_2"}
        },
        %{
          case_id: "**generated-uuid**",
          index_case_id: new_index_case.id,
          accession_number: "not_in_commcare_accession_number",
          data: %{"tid" => "not_in_commcare"}
        }
      ])
    end

    test "adds any missing lab results to the transfer-destination index case if it already exists in the DB", context do
      {:ok, destination_index_case} =
        %{
          data: %{"thing1" => "value-from-eclrs-1", "thing2" => "value-from-eclrs-2"},
          case_id: context.destination_case_data.case_id,
          person_id: context.person.id,
          county_id: context.destination_county.id
        }
        |> Commcare.create_index_case()

      {:ok, _old_lab_result} =
        %{
          data: context.source_county_lab_result_1.data,
          index_case_id: destination_index_case.id,
          accession_number: context.source_county_lab_result_1.accession_number
        }
        |> Commcare.create_lab_result()

      {:ok, found_index_case, :found} =
        Transfer.find_or_create_transferred_index_case_and_lab_results(
          context.source_index_case,
          context.destination_case_data,
          context.destination_county.id
        )

      assert found_index_case == destination_index_case

      Commcare.get_lab_results(found_index_case)
      |> Enum.map(& &1.accession_number)
      |> Enum.sort()
      |> assert_eq(~w[in_commcare_1_accession_number in_commcare_2_accession_number not_in_commcare_accession_number])
    end
  end
end
