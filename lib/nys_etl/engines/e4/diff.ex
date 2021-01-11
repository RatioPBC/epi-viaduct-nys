defmodule NYSETL.Engines.E4.Diff do
  alias NYSETL.Commcare.IndexCase
  alias NYSETL.Engines.E4.PatientCaseData

  def case_diff_summary(%IndexCase{}, nil) do
    %{
      patient_case: %{
        update: 0,
        create: 1
      }
    }
  end

  def case_diff_summary(%IndexCase{data: index_case_data}, %PatientCaseData{properties: patient_case_properties}) do
    %{
      patient_case: %{
        update: if(Map.equal?(index_case_data, patient_case_properties), do: 0, else: 1),
        create: 0
      }
    }
  end
end
