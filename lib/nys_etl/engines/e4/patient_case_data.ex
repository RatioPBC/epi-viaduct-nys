defmodule NYSETL.Engines.E4.PatientCaseData do
  defstruct ~w{case_id county_domain data external_id owner_id properties transfer_destination_county_id}a

  alias NYSETL.Engines.E4.PatientCaseData

  def new(data, county_domain \\ nil) do
    properties = data |> Map.get("properties", %{})

    %PatientCaseData{
      case_id: data["case_id"],
      county_domain: county_domain,
      data: data,
      external_id: properties["external_id"],
      owner_id: properties["owner_id"],
      properties: properties,
      transfer_destination_county_id: properties["transfer_destination_county_id"]
    }
  end
end
