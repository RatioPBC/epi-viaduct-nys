defmodule NYSETL.Engines.E4.Transfer do
  alias NYSETL.Commcare
  alias NYSETL.Extra

  @doc """
  Looks for an existing index case for the provided case_id and county_id, and returns it if found.

  Otherwise, creates a new index case and lab results that mirror an index case and lab results that have been transferred
  in commcare.

  The data field of the new index case is the result of merging the data field from the old index case plus
  the data from the newly-transferred case in commcare.

  The data fields of the lab results belonging to the new index case ONLY get data from the old lab results,
  not from the newly-transferred lab results in commcare, because the current thinking is that ECLRS data is
  more correct for lab results.
  """
  def find_or_create_transferred_index_case_and_lab_results(index_case, destination_case_data, destination_county_id) do
    case Commcare.get_index_case(case_id: destination_case_data.case_id, county_id: destination_county_id) do
      {:ok, transferred_index_case} ->
        {:ok, transferred_index_case, :found}

      {:error, :not_found} ->
        {:ok, new_index_case} = create_transferred_index_case(index_case, destination_case_data, destination_county_id)

        index_case
        |> Commcare.get_lab_results()
        |> Enum.each(&create_transferred_lab_result(new_index_case, &1, destination_case_data))

        {:ok, new_index_case, :created}
    end
  end

  defp create_transferred_index_case(original_index_case, destination_case_data, destination_county_id) do
    Commcare.create_index_case(%{
      data: Extra.Map.merge_empty_fields(destination_case_data.properties, original_index_case.data),
      case_id: destination_case_data.case_id,
      county_id: destination_county_id,
      person_id: original_index_case.person_id
    })
  end

  defp create_transferred_lab_result(transferred_index_case, old_lab_result, destination_case_data) do
    found_or_blank_case_id = find_commcare_case_id_by_accession_number(old_lab_result.accession_number, destination_case_data)

    %{
      data: old_lab_result.data,
      index_case_id: transferred_index_case.id,
      accession_number: old_lab_result.accession_number,
      case_id: found_or_blank_case_id
    }
    |> Commcare.create_lab_result()
    |> case do
      {:ok, lab_result} -> {:ok, lab_result}
      error -> throw(error)
    end
  end

  defp find_commcare_case_id_by_accession_number(accession_number, %{data: %{"child_cases" => child_cases}})
       when is_map(child_cases) do
    child_cases
    |> Enum.find_value(fn
      {case_id, %{"case_type" => "lab_result", "properties" => %{"accession_number" => ^accession_number}} = _case_data} ->
        case_id

      _other ->
        nil
    end)
  end

  defp find_commcare_case_id_by_accession_number(_accession_number, _case_data), do: nil
end
