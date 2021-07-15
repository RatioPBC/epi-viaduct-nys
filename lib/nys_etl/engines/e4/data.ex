defmodule NYSETL.Engines.E4.Data do
  alias NYSETL.Commcare
  alias Euclid.Extra

  @keys_to_drop ~w{
    assigned_to_primary_checkin_case_id
    assigned_to_primary_name
    assigned_to_primary_username
    assigned_to_temp_checkin_case_id
    assigned_to_temp_name
    assigned_to_temp_username
  }

  def from_index_case(index_case, county_location_id, date_modified) do
    lab_results = Commcare.get_lab_results(index_case)
    date_modified_as_iso8601 = date_modified |> Extra.DateTime.to_iso8601(:rounded)

    data =
      index_case.data
      |> Map.put("owner_id", county_location_id)
      |> Map.put("new_lab_result_specimen_collection_date", new_lab_result_specimen_collection_date(index_case, lab_results))
      |> Map.put("new_lab_result_received_date", new_lab_result_received_date(index_case, lab_results))
      |> Map.put("new_lab_result_received", "yes")
      |> Map.drop(@keys_to_drop)

    %{
      index_case: %{
        case_id: index_case.case_id,
        case_type: "patient",
        case_name: index_case.data["full_name"],
        data: data,
        date_modified: date_modified_as_iso8601,
        owner_id: county_location_id
      },
      lab_results: lab_results |> Enum.map(&format_lab_result(&1, index_case.case_id))
    }
  end

  @keys_to_drop ~w{
    created_manually
    lab_result_notes
    most_recent_lab_result_note
  }

  defp format_lab_result(lab_result, parent_case_id) do
    %{
      case_id: lab_result.case_id,
      parent_case_id: parent_case_id,
      owner_id: "-",
      data:
        lab_result.data
        |> Map.put("accession_number", lab_result.accession_number)
        |> Map.put("owner_id", "-")
        |> Map.drop(@keys_to_drop)
    }
  end

  defp new_lab_result_specimen_collection_date(index_case, lab_results) do
    lab_results
    |> Enum.map(fn lab_result -> lab_result.data["specimen_collection_date"] end)
    |> Enum.max(fn -> nil end)
    |> case do
      nil -> index_case.inserted_at |> NaiveDateTime.to_date() |> Date.to_iso8601()
      date -> date
    end
  end

  def new_lab_result_received_date(index_case, lab_results) do
    lab_results
    |> Enum.map(fn lab_result -> lab_result.inserted_at end)
    |> Enum.max(NaiveDateTime, fn -> nil end)
    |> case do
      nil -> index_case.inserted_at
      datetime -> datetime
    end
    |> NaiveDateTime.to_date()
    |> Date.to_iso8601()
  end
end
