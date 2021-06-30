defmodule NYSETL.Engines.E5.Processor do
  @moduledoc """
  Run for each patient case extracted from CommCare.

  * case_id already present in our DB:
    * update it with changes from CommCare (but ignore any new lab results)
  * case_id does not exist, Person exists and can be matched by dob | last_name | first_name:
    * create an IndexCase and LabResult record(s)
  * case_id does not exist, Person cannot be matched:
    * create a Person, IndexCase and LabResult record(s)
  """

  alias Euclid.Exists
  alias Euclid.Extra
  alias NYSETL.Commcare

  require Logger

  def process(case: patient_case, county: county) do
    with {:error, :not_found} <- find_and_update_index_case(patient_case, county),
         {_case_id, patient_key, dob, lab_results} <- extract_case_data(patient_case),
         {:ok, person, finder} <- find_person(patient_case, dob, patient_key) || create_person(patient_case) do
      {:ok, index_case} = create_index_case(patient_case, person, county)
      index_case |> create_lab_results(lab_results, county)
      {:ok, index_case, finder}
    else
      {:ok, %Commcare.IndexCase{} = index_case} ->
        {:ok, index_case, :already_exists}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset.errors}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def extract_case_data(%{"closed" => true}), do: {:error, :closed}

  def extract_case_data(%{"properties" => %{"final_disposition" => final_disposition}})
      when final_disposition in ["registered_in_error", "duplicate", "not_a_case"],
      do: {:error, :final_disposition}

  def extract_case_data(%{"properties" => %{"patient_type" => "pui", "current_status" => "closed"}}), do: {:error, :closed}

  def extract_case_data(%{"properties" => %{"stub" => "yes"}}), do: {:error, :stub}

  def extract_case_data(%{"properties" => %{"transfer_status" => transfer_status}})
      when transfer_status in ["pending", "sent"],
      do: {:error, :transfer_status}

  def extract_case_data(patient_case) do
    case_id = patient_case["case_id"]
    lab_results = lab_results(patient_case)
    patient_key = find_patient_key(patient_case, lab_results)
    dob = parse_dob(patient_case)

    {case_id, patient_key, dob, lab_results}
  end

  def create_person(%{"properties" => properties} = patient_case) do
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
      {:ok, person} -> {:ok, person, :new_person}
      other -> other
    end
  end

  def create_index_case(case, %Commcare.Person{} = person, county) do
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

  def create_lab_results(%Commcare.IndexCase{} = index_case, [], _county), do: index_case

  def create_lab_results(%Commcare.IndexCase{} = index_case, lab_results, county) do
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

  def find_and_update_index_case(patient_case, county) do
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
  end

  def find_person(patient_case, dob, patient_key) do
    Logger.debug("[#{__MODULE__}] trying to find a person matching index_case case_id=#{patient_case.case_id}")

    find_person(patient_key: patient_key) || find_person(patient_case, dob: dob)
  end

  def find_person(patient_key: patient_key) do
    Commcare.get_person(patient_key: patient_key)
    |> case do
      {:ok, person} -> {:ok, person, :patient_key}
      {:error, :not_found} -> nil
    end
  end

  def find_person(_case, dob: nil), do: nil

  def find_person(%{"properties" => %{"first_name" => first_name, "last_name" => last_name}}, dob: dob)
      when is_binary(first_name) and is_binary(last_name) do
    Commcare.get_person(
      dob: dob,
      name_first: first_name |> String.upcase(),
      name_last: last_name |> String.upcase()
    )
    |> case do
      {:ok, person} -> {:ok, person, :dob}
      {:error, :not_found} -> nil
    end
  end

  def find_person(%{"properties" => %{"full_name" => full_name}}, dob: dob)
      when is_binary(full_name) do
    Commcare.get_person(
      dob: dob,
      full_name: full_name
    )
    |> case do
      {:ok, person} -> {:ok, person, :full_name}
      {:error, :not_found} -> nil
    end
  end

  def find_patient_key(case, lab_results) do
    patient_key_from_external_id(case["properties"]["external_id"]) ||
      patient_key_from_name_and_id(case["properties"]["name_and_id"]) ||
      patient_key_from_lab_result(lab_results)
  end

  def parse_dob(%{"properties" => %{"dob" => <<year::binary-size(4), "-", month::binary-size(2), "-", day::binary-size(2)>>}}),
    do: Date.from_erl!({String.to_integer(year), String.to_integer(month), String.to_integer(day)})

  def parse_dob(_), do: nil

  def patient_key_from_external_id(nil), do: nil
  def patient_key_from_external_id(""), do: nil

  def patient_key_from_external_id(binary) when is_binary(binary) do
    binary
    |> String.split("#")
    |> Enum.at(1)
  end

  def patient_key_from_lab_result([]), do: nil

  def patient_key_from_lab_result(lab_results) do
    lab_results
    |> Extra.Enum.pluck("properties")
    |> Extra.Enum.pluck("external_id")
    |> Extra.Enum.compact()
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

  def patient_key_from_name_and_id(nil), do: nil

  def patient_key_from_name_and_id(binary) when is_binary(binary) do
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
        Exists.present?(child_cases["properties"]["accession_number"])
    end)
  end

  def case_is_a_stub?(%{"properties" => %{"stub" => "yes"}}), do: true
  def case_is_a_stub?(_), do: false

  def case_has_lab_result?(%{"child_cases" => child_cases}),
    do: child_cases |> Map.values() |> Enum.any?(&case_is_a_lab_result?/1)

  def case_has_lab_result?(_), do: false

  def case_is_a_lab_result?(%{"properties" => %{"case_type" => "lab_result"}}), do: true
  def case_is_a_lab_result?(_), do: false
end
