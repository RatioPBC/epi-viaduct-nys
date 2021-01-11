defmodule NYSETL.Engines.E4.DiffTest do
  use NYSETL.DataCase

  alias NYSETL.Commcare.IndexCase
  alias NYSETL.Engines.E4.Diff
  alias NYSETL.Engines.E4.PatientCaseData

  describe "case_diff_summary" do
    test "returns the correct stats when the index_case and patient case are not equivalent" do
      expected = %{
        patient_case: %{
          update: 1,
          create: 0
        }
      }

      index_case = %IndexCase{data: %{"full_name" => "Original Full Name"}}

      patient_case_data =
        PatientCaseData.new(%{
          "properties" => %{
            "full_name" => "Different Full Name"
          }
        })

      Diff.case_diff_summary(index_case, patient_case_data)
      |> assert_eq(expected, only: [:patient_case])
    end

    test "returns the correct stats when the index_case and patient case are equivalent" do
      expected = %{
        patient_case: %{
          update: 0,
          create: 0
        }
      }

      index_case = %IndexCase{data: %{"full_name" => "Original Full Name"}}

      patient_case_data =
        PatientCaseData.new(%{
          "properties" => %{
            "full_name" => "Original Full Name"
          }
        })

      Diff.case_diff_summary(index_case, patient_case_data)
      |> assert_eq(expected, only: [:patient_case])
    end
  end

  test "returns the correct stats when the index_case exists and fetched_commcare_data is empty" do
    expected = %{
      patient_case: %{
        update: 0,
        create: 1
      }
    }

    index_case = %IndexCase{data: %{"full_name" => "Original Full Name"}}

    Diff.case_diff_summary(index_case, nil)
    |> assert_eq(expected, only: [:patient_case])
  end
end
