defmodule NYSETL.Commcare.CaseImporter do
  @moduledoc """
  Run for a patient case extracted or forwarded from CommCare.

  * case_id already present in our DB:
    * update it with changes from CommCare (but ignore any new lab results)
  * case_id does not exist, Person exists and can be matched by dob | last_name | first_name:
    * create an IndexCase and LabResult record(s)
  * case_id does not exist, Person cannot be matched:
    * create a Person, IndexCase and LabResult record(s)
  """
  use Oban.Worker, queue: :commcare, unique: [period: :infinity, states: [:available, :scheduled, :retryable]]

  require Logger

  alias Euclid.Term
  alias NYSETL.Commcare
  alias NYSETL.Commcare.Api
  alias NYSETL.Commcare.County

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"commcare_case_id" => commcare_case_id, "domain" => domain}}) do
    {:ok, patient_case} = Api.get_case(commcare_case_id: commcare_case_id, county_domain: domain)
    {:ok, county} = County.get(domain: domain)

    import_case(case: patient_case, county: county)
  end

  def import_case(case: %{"properties" => %{"case_type" => "patient"}} = patient_case, county: county) do
    with {:error, :not_found} <- find_and_update_index_case(patient_case, county),
         {_case_id, patient_key, dob, lab_results} <- extract_case_data(patient_case),
         {:ok, person} <- find_person(patient_case, dob, patient_key) || create_person(patient_case) do
      Commcare.update_person(person, fn ->
        {:ok, index_case} = create_index_case(patient_case, person, county)
        index_case |> create_lab_results(lab_results, county)
        :ok
      end)
    else
      {:ok, %Commcare.IndexCase{}} ->
        :ok

      {:error, %Ecto.Changeset{errors: errors}} ->
        {:discard, errors}

      {:error, reason} ->
        {:error, reason}

      {:discard, reason} ->
        {:discard, reason}
    end
  end

  def import_case(case: %{"case_id" => case_id, "properties" => %{"case_type" => case_type}}, county: _county) do
    message = "#{__MODULE__}: Can only import `patient` cases. #{case_id} is a `#{case_type}`."
    Sentry.capture_message(message)
    {:discard, message}
  end

  defp extract_case_data(%{"closed" => true}), do: {:discard, :closed}

  defp extract_case_data(%{"properties" => %{"final_disposition" => final_disposition}})
       when final_disposition in ["registered_in_error", "duplicate", "not_a_case"],
       do: {:discard, :final_disposition}

  defp extract_case_data(%{"properties" => %{"patient_type" => "pui", "current_status" => "closed"}}), do: {:discard, :closed}

  defp extract_case_data(%{"properties" => %{"stub" => "yes"}}), do: {:discard, :stub}

  defp extract_case_data(%{"properties" => %{"transfer_status" => transfer_status}})
       when transfer_status in ["pending", "sent"],
       do: {:discard, :transfer_status}

  defp extract_case_data(patient_case) do
    case_id = patient_case["case_id"]
    lab_results = lab_results(patient_case)
    patient_key = find_patient_key(patient_case, lab_results)
    dob = parse_dob(patient_case)

    {case_id, patient_key, dob, lab_results}
  end

  defp create_person(%{"properties" => properties} = patient_case) do
    Logger.debug("[#{__MODULE__}] trying to create a person matching index_case case_id=#{patient_case.case_id}")

    first_name = properties["first_name"] && String.upcase(properties["first_name"])
    last_name = properties["last_name"] && String.upcase(properties["last_name"])
    dob = properties["dob"]

    %{
      data: %{},
      patient_keys: [],
      name_last: last_name,
      name_first: first_name,
      dob: dob
    }
    |> Commcare.create_person()
    |> case do
      {:ok, person} -> {:ok, person}
      other -> other
    end
  end

  defp create_index_case(case, %Commcare.Person{} = person, county) do
    case_id = case["case_id"]

    {:ok, index_case} =
      %{
        case_id: case_id,
        data: case["properties"],
        county_id: county.fips,
        person_id: person.id
      }
      |> Commcare.create_index_case()

    :telemetry.execute([:extractor, :commcare, :index_case, :created], %{count: 1})
    Logger.info("[#{__MODULE__}] created index_case case_id=#{case_id} for person_id=#{person.id}, county=#{county.domain}")
    index_case |> Commcare.save_event("retrieved_from_commcare")
    {:ok, index_case}
  end

  defp create_lab_results(%Commcare.IndexCase{} = index_case, [], _county), do: index_case

  defp create_lab_results(%Commcare.IndexCase{} = index_case, lab_results, county) do
    lab_results
    |> Enum.each(fn commcare_lab_result ->
      %{
        case_id: commcare_lab_result["case_id"],
        data: commcare_lab_result["properties"],
        index_case_id: index_case.id,
        accession_number: commcare_lab_result["properties"]["accession_number"]
      }
      |> Commcare.create_lab_result()
      |> case do
        {:ok, lab_result} ->
          :telemetry.execute([:extractor, :commcare, :lab_result, :created], %{count: 1})

          Logger.info("[#{__MODULE__}] created lab_result=#{lab_result.case_id} for index_case case_id=#{index_case.case_id} county=#{county.domain}")

          {:ok, lab_result}

        error ->
          throw(error)
      end
    end)
  end

  defp find_and_update_index_case(patient_case, county) do
    with {:ok, person} <- Commcare.get_person(case_id: patient_case["case_id"]) do
      Commcare.update_person(person, fn ->
        Commcare.get_index_case(case_id: patient_case["case_id"], county_id: county.fips)
        |> case do
          {:error, :not_found} ->
            {:error, :not_found}

          {:ok, index_case} ->
            Commcare.update_index_case_from_commcare_data(index_case, patient_case)
            |> case do
              {:ok, ^index_case} ->
                Logger.info(
                  "[#{__MODULE__}] not modified index_case case_id=#{index_case.case_id} for person_id=#{index_case.person_id}, county=#{county.domain}"
                )

                {:ok, index_case}

              {:ok, index_case} ->
                :telemetry.execute([:extractor, :commcare, :index_case, :already_exists], %{count: 1})

                Logger.info(
                  "[#{__MODULE__}] updated index_case case_id=#{index_case.case_id} for person_id=#{index_case.person_id}, county=#{county.domain}"
                )

                index_case |> Commcare.save_event("updated_from_commcare")

                {:ok, index_case}
            end
        end
      end)
    else
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp find_person(patient_case, dob, patient_key) do
    Logger.debug("[#{__MODULE__}] trying to find a person matching index_case case_id=#{patient_case.case_id}")

    find_person(patient_key: patient_key) || find_person(patient_case, dob: dob)
  end

  defp find_person(patient_key: patient_key) do
    Commcare.get_person(patient_key: patient_key)
    |> case do
      {:ok, person} -> {:ok, person}
      {:error, :not_found} -> nil
    end
  end

  defp find_person(_case, dob: nil), do: nil

  defp find_person(%{"properties" => %{"first_name" => first_name, "last_name" => last_name}}, dob: dob)
       when is_binary(first_name) and is_binary(last_name) do
    Commcare.get_person(
      dob: dob,
      name_first: first_name |> String.upcase(),
      name_last: last_name |> String.upcase()
    )
    |> case do
      {:ok, person} -> {:ok, person}
      {:error, :not_found} -> nil
    end
  end

  defp find_person(%{"properties" => %{"full_name" => full_name}}, dob: dob)
       when is_binary(full_name) do
    Commcare.get_person(
      dob: dob,
      full_name: full_name
    )
    |> case do
      {:ok, person} -> {:ok, person}
      {:error, :not_found} -> nil
    end
  end

  defp find_patient_key(case, lab_results) do
    patient_key_from_external_id(case["properties"]["external_id"]) ||
      patient_key_from_name_and_id(case["properties"]["name_and_id"]) ||
      patient_key_from_lab_result(lab_results)
  end

  defp parse_dob(%{"properties" => %{"dob" => <<year::binary-size(4), "-", month::binary-size(2), "-", day::binary-size(2)>>}}),
    do: Date.from_erl!({String.to_integer(year), String.to_integer(month), String.to_integer(day)})

  defp parse_dob(_), do: nil

  defp patient_key_from_external_id(nil), do: nil
  defp patient_key_from_external_id(""), do: nil

  defp patient_key_from_external_id(binary) when is_binary(binary) do
    binary
    |> String.split("#")
    |> Enum.at(1)
  end

  defp patient_key_from_lab_result([]), do: nil

  defp patient_key_from_lab_result(lab_results) do
    lab_results
    |> Euclid.Enum.pluck("properties")
    |> Euclid.Enum.pluck("external_id")
    |> Euclid.Enum.compact()
    |> List.first()
    |> case do
      nil ->
        nil

      value ->
        value
        |> String.split("#")
        |> Enum.at(1)
    end
  end

  defp patient_key_from_name_and_id(nil), do: nil

  defp patient_key_from_name_and_id(binary) when is_binary(binary) do
    Regex.named_captures(~r|.+\(.+#(?<patient_key>\d+)\)|, binary)
    |> case do
      %{"patient_key" => patient_key} -> patient_key
      _ -> nil
    end
  end

  defp lab_results(case) do
    case["child_cases"]
    |> Map.values()
    |> Enum.filter(fn child_cases ->
      child_cases["properties"]["case_type"] == "lab_result" &&
        Term.present?(child_cases["properties"]["accession_number"])
    end)
  end
end
