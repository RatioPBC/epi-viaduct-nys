defmodule NYSETL.Engines.E2.Processor do
  @moduledoc """
  For a TestResult record, decide the following

  * Find or create a Person record, based on :patient_key or unique (dob/last_name/first_name)
  * Create or update one more IndexCase records for this county
  * Create or update a LabResult record for the IndexCase

  ## Edge cases

  * Pre-existing data in CommCare may not be well deduplicated for people. If we have deduped a person,
    but there are multiple IndexCase records for that person in this county, creation of new LabResult
    records is duplicated across all IndexCase records.
  """

  require Logger

  alias NYSETL.Commcare
  alias NYSETL.ECLRS
  alias NYSETL.Format

  require Logger

  def process(test_result, ignore_before \\ Application.get_env(:nys_etl, :eclrs_ignore_before_timestamp)) do
    with :ok <- processable?(test_result, ignore_before),
         {:ok, county} <- get_county(test_result.county_id),
         {:ok, person} <- find_or_create_person(test_result) do
      person
      |> find_or_create_index_cases(test_result, county)
      |> Enum.map(&process_one(&1, test_result, county))
      |> maybe_register_summary_event(test_result)

      :ok
    else
      {:non_participating_county, county} ->
        ECLRS.save_event(test_result,
          type: "test_result_ignored",
          data: %{reason: "test_result is for fips #{county.fips} (a non-participating county)"}
        )

        :ok

      {:unprocessable, threshold} ->
        Logger.warn(
          "[#{__MODULE__}}] ignoring test_result_id=#{test_result.id} because its eclrs_create_date was older than eclrs_ignore_before_timestamp"
        )

        ECLRS.save_event(test_result, type: "test_result_ignored", data: %{reason: "test_result older than #{threshold}"})
        :ok

      {status, reason} ->
        Sentry.capture_message("Mishandled case", extra: %{test_result_id: test_result.id, status: status, reason: reason})
        :error

      _ ->
        Sentry.capture_message("Unhandled case", extra: %{test_result_id: test_result.id})
        :error
    end
  end

  defp processable?(%ECLRS.TestResult{eclrs_create_date: eclrs_create_date}, ignore_before) do
    if :gt == DateTime.compare(eclrs_create_date, ignore_before),
      do: :ok,
      else: {:unprocessable, ignore_before}
  end

  defp process_one({ic_creation_status, index_case}, test_result, county) do
    {:ok, lr_creation_status} = create_or_update_lab_result(index_case, test_result, county)
    {ic_creation_status, lr_creation_status}
  end

  defp maybe_register_summary_event(list, test_result) do
    if Enum.all?(list, &(&1 == {:untouched, :untouched})) do
      {:ok, _} = ECLRS.save_event(test_result, "no_new_information")
    end
  end

  @doc """
  Returns a tuple where the first element is a map of additions and the second element is a map of updated values.

  ## Examples

      iex> a = %{a: 1, b: 2, z: 26}
      iex> b = %{a: 1, b: 3, y: 25}
      iex> diff(a, b)
      {%{y: 25}, %{b: 3}}
  """
  @spec diff(map(), map(), keyword()) :: {map(), map()}
  def diff(a, b, opts \\ [])

  def diff(a, b, opts) do
    prefer_right = opts |> Keyword.get(:prefer_right, [])
    a = Euclid.Extra.Map.stringify_keys(a)
    b = Euclid.Extra.Map.stringify_keys(b)
    a_set = MapSet.new(a)
    b_set = MapSet.new(b)

    merged_set = a |> Map.merge(b, &pick_merge_value(&1, &2, &3, prefer_right)) |> MapSet.new()

    updates = b_set |> MapSet.difference(merged_set)
    additions = b_set |> MapSet.difference(a_set) |> MapSet.difference(updates)
    {Enum.into(additions, %{}), Enum.into(updates, %{})}
  end

  defp pick_merge_value(_key, av, bv, _) when av == "", do: bv

  defp pick_merge_value(key, av, bv, prefer_right) do
    if key in prefer_right,
      do: bv || av,
      else: av || bv
  end

  defp find_or_create_person(test_result) do
    ECLRS.fingerprint(test_result)
    |> NYSETL.Engines.E1.Cache.transaction(fn _cache ->
      find_person_by_patient_key(test_result) || reuse_person_by_name_and_dob(test_result) || create_person(test_result)
    end)
  end

  defp find_person_by_patient_key(test_result) do
    Commcare.get_person(patient_key: test_result.patient_key)
    |> case do
      {:ok, person} ->
        ECLRS.save_event(test_result, type: "person_matched", data: %{person_id: person.id})
        :telemetry.execute([:transformer, :person, :found], %{count: 1})
        {:ok, person}

      {:error, :not_found} ->
        nil
    end
  end

  defp reuse_person_by_name_and_dob(%{patient_dob: nil}), do: nil
  defp reuse_person_by_name_and_dob(%{patient_name_first: nil}), do: nil
  defp reuse_person_by_name_and_dob(%{patient_name_last: nil}), do: nil

  defp reuse_person_by_name_and_dob(test_result) do
    Commcare.get_person(
      dob: test_result.patient_dob,
      name_first: first_name(test_result),
      name_last: test_result.patient_name_last |> String.upcase()
    )
    |> case do
      {:ok, person} ->
        ECLRS.save_event(test_result, type: "person_added_patient_key", data: %{person_id: person.id})
        :telemetry.execute([:transformer, :person, :added_patient_key], %{count: 1})
        Commcare.add_patient_key(person, test_result.patient_key)

      {:error, :not_found} ->
        nil
    end
  end

  defp create_person(test_result) do
    :telemetry.execute([:transformer, :person, :created], %{count: 1})

    name_last = if test_result.patient_name_last, do: test_result.patient_name_last |> String.upcase()

    {:ok, person} =
      %{
        data: %{},
        patient_keys: [test_result.patient_key],
        name_last: name_last,
        name_first: first_name(test_result),
        dob: test_result.patient_dob
      }
      |> Commcare.create_person()

    ECLRS.save_event(test_result, type: "person_created", data: %{person_id: person.id})

    Logger.info("[#{__MODULE__}] created person #{person.id} patient_key=#{test_result.patient_key} from test_result id=#{test_result.id}")

    {:ok, person}
  end

  defp find_or_create_index_cases(person, test_result, commcare_county) do
    with {:ok, index_cases} <-
           Commcare.get_index_cases(person, county_id: commcare_county.fips, accession_number: test_result.request_accession_number),
         open_cases when open_cases != [] <- index_cases |> Enum.filter(&is_open_case?/1) do
      Enum.map(index_cases, &update_index_case(&1, person, test_result, commcare_county))
    else
      {:error, :not_found} -> [{:created, create_index_case(person, test_result, commcare_county)}]
      [] -> [{:created, create_index_case(person, test_result, commcare_county)}]
    end
  end

  defp is_open_case?(%Commcare.IndexCase{closed: true}), do: false

  defp is_open_case?(%Commcare.IndexCase{data: %{"final_disposition" => final_disposition}})
       when final_disposition in ["registered_in_error", "duplicate", "not_a_case"],
       do: false

  defp is_open_case?(%Commcare.IndexCase{data: %{"stub" => "yes"}}), do: false

  defp is_open_case?(%Commcare.IndexCase{data: %{"current_status" => "closed", "patient_type" => "pui"}}), do: false

  defp is_open_case?(%Commcare.IndexCase{data: %{"transfer_status" => transfer_status}})
       when transfer_status in ["pending", "sent"],
       do: false

  defp is_open_case?(_index_case), do: true

  defp update_index_case(%Commcare.IndexCase{} = index_case, person, test_result, commcare_county) do
    old_data = index_case.data
    new_data = to_index_case_data(test_result, person, commcare_county) |> Euclid.Extra.Map.stringify_keys()

    {additions, updates} = old_data |> diff(new_data, prefer_right: ["has_phone_number"])

    merged_data = old_data |> NYSETL.Extra.Map.merge_empty_fields(additions)
    address_complete = address_complete?(merged_data)

    {additions, updates} =
      if address_complete != old_data["address_complete"] do
        additions = additions |> Map.put("address_complete", address_complete)
        updates = updates |> Map.drop(["address_complete"])
        {additions, updates}
      else
        {additions, updates}
      end

    NYSETL.ChangeLog.changeset(%{
      source_type: "test_result",
      source_id: test_result.id,
      destination_type: "index_case",
      destination_id: index_case.id,
      previous_state: old_data,
      applied_changes: additions,
      dropped_changes: updates
    })
    |> NYSETL.Repo.insert!()

    change_metadata = %{
      source_type: "test_result",
      source_id: test_result.id,
      dropped_changes: updates
    }

    {:ok, index_case} = index_case |> Commcare.update_index_case(%{data: Map.merge(old_data, additions)}, change_metadata)
    modification_status = save_index_case_diff_event(index_case, additions, test_result)
    {modification_status, index_case}
  end

  defp save_index_case_diff_event(index_case, changes_to_be_made, test_result) do
    if Enum.any?(changes_to_be_made) do
      ECLRS.save_event(test_result, type: "index_case_updated", data: %{index_case_id: index_case.id})
      Commcare.save_event(index_case, type: "index_case_updated", data: %{test_result_id: test_result.id})
      :updated
    else
      ECLRS.save_event(test_result, type: "index_case_untouched", data: %{index_case_id: index_case.id})
      Commcare.save_event(index_case, type: "index_case_untouched", data: %{test_result_id: test_result.id})
      :untouched
    end
  end

  defp create_index_case(person, test_result, commcare_county) do
    %{
      data: to_index_case_data(test_result, person, commcare_county) |> Euclid.Extra.Map.stringify_keys(),
      county_id: commcare_county.fips,
      person_id: person.id
    }
    |> Commcare.create_index_case()
    |> case do
      {:ok, index_case} ->
        ECLRS.save_event(test_result, type: "index_case_created", data: %{index_case_id: index_case.id})
        Commcare.save_event(index_case, type: "index_case_created", data: %{test_result_id: test_result.id})
        Logger.info("[#{__MODULE__}] test_result #{test_result.id} created index case case_id=#{index_case.case_id} for person id=#{person.id}")
        index_case

      other ->
        Logger.info("[#{__MODULE__}] failed to create index case for person id=#{person.id}")
        other
    end
  end

  defp create_or_update_lab_result(index_case, test_result, commcare_county) do
    Commcare.get_lab_results(index_case, accession_number: test_result.request_accession_number)
    |> case do
      {:error, :not_found} ->
        {:ok, _lab_result, :created} = create_lab_result(index_case, test_result, commcare_county)
        {:ok, :created}

      {:ok, lab_results} ->
        lab_results
        |> Enum.map(fn lab_result ->
          {:ok, _lab_result, status} = update_lab_result(lab_result, index_case, test_result, commcare_county)
          status
        end)
        |> Enum.all?(&(&1 == :untouched))
        |> case do
          true -> {:ok, :untouched}
          _ -> {:ok, :updated}
        end
    end
  end

  defp create_lab_result(index_case, test_result, commcare_county) do
    %{
      data: to_lab_result_data(index_case, test_result, commcare_county),
      index_case_id: index_case.id,
      accession_number: test_result.request_accession_number
    }
    |> Commcare.create_lab_result()
    |> case do
      {:ok, lab_result} ->
        ECLRS.save_event(test_result, type: "lab_result_created", data: %{lab_result_id: lab_result.id, index_case_id: index_case.id})
        Commcare.save_event(index_case, type: "lab_result_created", data: %{test_result_id: test_result.id})
        {:ok, lab_result, :created}

      error ->
        error
    end
  end

  defp update_lab_result(lab_result, index_case, test_result, commcare_county) do
    new_data = to_lab_result_data(index_case, test_result, commcare_county) |> Euclid.Extra.Map.stringify_keys()
    merged = new_data |> NYSETL.Extra.Map.merge_empty_fields(lab_result.data)
    {additions, updates} = lab_result.data |> diff(merged)
    data = lab_result.data |> Map.merge(additions)

    change_metadata = %{
      source_type: "test_result",
      source_id: test_result.id,
      dropped_changes: updates
    }

    lab_result
    |> Commcare.update_lab_result(%{data: data}, change_metadata)
    |> case do
      {:ok, updated_lab_result} ->
        NYSETL.ChangeLog.changeset(%{
          source_type: "test_result",
          source_id: test_result.id,
          destination_type: "lab_result",
          destination_id: updated_lab_result.id,
          previous_state: updated_lab_result.data,
          applied_changes: additions,
          dropped_changes: updates
        })
        |> NYSETL.Repo.insert!()

        result =
          if data != lab_result.data do
            ECLRS.save_event(test_result, type: "lab_result_updated", data: %{lab_result_id: lab_result.id, index_case_id: index_case.id})
            Commcare.save_event(index_case, type: "lab_result_updated", data: %{test_result_id: test_result.id})
            :updated
          else
            ECLRS.save_event(test_result, type: "lab_result_untouched", data: %{lab_result_id: lab_result.id, index_case_id: index_case.id})
            Commcare.save_event(index_case, type: "lab_result_untouched", data: %{test_result_id: test_result.id})
            :untouched
          end

        {:ok, updated_lab_result, result}

      error ->
        error
    end
  end

  defp get_county(county_id) do
    NYSETL.Commcare.County.get(fips: county_id)
    |> case do
      {:ok, county} -> {:ok, county}
      {:error, _} -> NYSETL.Commcare.County.statewide_county()
      {:non_participating, county} -> {:non_participating_county, county}
    end
  end

  defp address(%{patient_address_1: patient_address_1, patient_city: patient_city, patient_zip: patient_zip}, state) do
    [patient_address_1, patient_city, state, patient_zip]
    |> Euclid.Extra.Enum.compact()
    |> Enum.join(", ")
  end

  defp address_complete?(%{"address_street" => patient_address_1, "address_city" => patient_city, "address_zip" => patient_zip}),
    do: address_complete?(%{address_street: patient_address_1, address_city: patient_city, address_zip: patient_zip})

  defp address_complete?(%{address_street: patient_address_1, address_city: patient_city, address_zip: patient_zip})
       when byte_size(patient_address_1) > 0 and byte_size(patient_city) > 0 and byte_size(patient_zip) > 0,
       do: "yes"

  defp address_complete?(_), do: "no"

  defp dob_known?(%Date{}), do: "yes"
  defp dob_known?(_), do: "no"

  defp first_name(%{patient_name_first: name}) when is_binary(name) do
    name |> String.split(" ") |> List.first() |> String.upcase()
  end

  defp first_name(_), do: nil

  defp gender(nil), do: {"", ""}

  defp gender(binary) when is_binary(binary) do
    binary
    |> String.upcase()
    |> case do
      "M" -> {"male", ""}
      "F" -> {"female", ""}
      _ -> {"other", binary}
    end
  end

  defp has_phone_number?(%{contact_phone_number: number}) when byte_size(number) > 0, do: "yes"
  defp has_phone_number?(_), do: "no"

  defp full_name(%{patient_name_first: first, patient_name_last: last}) do
    [first, last]
    |> Euclid.Extra.Enum.compact()
    |> Enum.join(" ")
  end

  defp state_for(<<zipcode::binary-size(5)>>), do: lookup_state(zipcode)
  defp state_for(<<zipcode::binary-size(5), "-", _suffix::binary-size(4)>>), do: lookup_state(zipcode)
  defp state_for(_), do: nil

  defp lookup_state(zipcode) do
    zipcode
    |> Zipcode.to_state()
    |> case do
      {:ok, abbr} -> abbr
      {:error, _} -> nil
    end
  end

  def to_index_case_data(test_result, person, commcare_county) do
    external_id = Commcare.external_id(person)

    %{
      doh_mpi_id: external_id,
      external_id: external_id,
      patient_type: "confirmed",
      new_lab_result_received: "yes"
    }
    |> Map.merge(to_index_case_data_address_block(test_result))
    |> Map.merge(to_index_case_data_county_block(commcare_county))
    |> Map.merge(to_index_case_data_person_block(test_result, external_id))
    |> Map.merge(to_index_case_data_rest(test_result))
    |> with_index_case_data_complete_fields()
  end

  def with_index_case_data_complete_fields(data) do
    data
    |> Map.merge(%{
      address_complete: address_complete?(data),
      has_phone_number: has_phone_number?(data)
    })
  end

  def to_index_case_data_address_block(test_result) do
    state = state_for(test_result.patient_zip)

    %{
      address: address(test_result, state),
      address_city: Format.format(test_result.patient_city),
      address_state: Format.format(state),
      address_street: Format.format(test_result.patient_address_1),
      address_zip: Format.format(test_result.patient_zip)
    }
  end

  def to_index_case_data_county_block(commcare_county) do
    %{
      address_county: Format.format(commcare_county.name),
      county_commcare_domain: Format.format(commcare_county.domain),
      county_display: Format.format(commcare_county.display),
      fips: Format.format(commcare_county.fips),
      gaz: Format.format(commcare_county.gaz),
      owner_id: Format.format(commcare_county.location_id)
    }
  end

  def to_index_case_data_person_block(test_result, external_id) do
    {gender, gender_other} = gender(test_result.patient_gender)

    %{
      contact_phone_number: test_result.patient_phone_home_normalized |> Format.format() |> Format.us_phone_number(),
      dob: Format.format(test_result.patient_dob),
      dob_known: dob_known?(test_result.patient_dob),
      first_name: test_result.patient_name_first,
      full_name: full_name(test_result),
      gender: gender,
      gender_other: gender_other,
      initials: initials(test_result.patient_name_first, test_result.patient_name_last),
      last_name: test_result.patient_name_last,
      name: full_name(test_result),
      name_and_id: "#{full_name(test_result)} (#{external_id})",
      phone_home: Format.format(test_result.patient_phone_home_normalized)
    }
  end

  def to_index_case_data_rest(test_result) do
    %{
      analysis_date: Format.format(test_result.result_analysis_date),
      case_import_date: Format.format(DateTime.utc_now()),
      eclrs_create_date: Format.format(test_result.eclrs_create_date)
    }
  end

  def to_lab_result_data(index_case, tr = %ECLRS.TestResult{}, commcare_county) do
    doh_mpi_id = index_case.data |> Map.get("external_id")

    %{
      accession_number: tr.request_accession_number,
      analysis_date: Format.format(tr.result_analysis_date),
      aoe_date: Format.format(tr.aoe_date),
      doh_mpi_id: doh_mpi_id,
      eclrs_congregate_care_resident: tr.eclrs_congregate_care_resident,
      eclrs_create_date: Format.format(tr.eclrs_create_date),
      eclrs_hospitalized: tr.eclrs_hospitalized,
      eclrs_icu: tr.eclrs_icu,
      eclrs_loinc: tr.result_loinc_code,
      eclrs_pregnant: tr.eclrs_pregnant,
      eclrs_symptom_onset_date: Format.format(tr.eclrs_symptom_onset_date),
      eclrs_symptomatic: tr.eclrs_symptomatic,
      employee_job_title: tr.employee_job_title,
      employee_number: tr.employee_number,
      employer_address: tr.employer_address,
      employer_name: tr.employer_name,
      employer_phone_2: tr.employer_phone_alt,
      employer_phone: tr.employer_phone,
      external_id: "#{doh_mpi_id}##{tr.patient_key}##{tr.request_accession_number}",
      first_test: tr.first_test,
      healthcare_employee: tr.healthcare_employee,
      lab_result: lab_result_text(tr.result),
      laboratory: tr.lab_name,
      name_employer_school: compact_join([tr.school_name, tr.employer_name], ", "),
      name: "#{doh_mpi_id} lab_result",
      ordering_facility_address: compact_join([tr.request_facility_address_1, tr.request_facility_address_2], "\n"),
      ordering_facility_city: tr.request_facility_city,
      ordering_facility_name: tr.request_facility_name,
      ordering_facility_phone: tr.request_phone_facility_normalized,
      ordering_provider_address: tr.request_provider_address_1,
      ordering_provider_city: tr.request_provider_city,
      ordering_provider_first_name: tr.request_provider_name_first,
      ordering_provider_last_name: tr.request_provider_name_last,
      ordering_provider_name: compact_join([tr.request_provider_name_first, tr.request_provider_name_last], " "),
      owner_id: commcare_county.location_id,
      parent_external_id: doh_mpi_id,
      parent_type: "patient",
      school_attended: tr.school_present,
      school_code: tr.school_code,
      school_district: tr.school_district,
      school_name: tr.school_name,
      school_visitor_type: tr.school_job_class,
      specimen_collection_date: Format.format(tr.request_collection_date),
      specimen_source: tr.request_specimen_source_name,
      test_type: tr.result_loinc_desc
    }
  end

  def lab_result_text(nil), do: "other"

  def lab_result_text(value) do
    match =
      Regex.scan(~r/positive|negative|inconclusive|invalid|unknown/i, String.downcase(value))
      |> List.flatten()
      |> List.first()

    match || "other"
  end

  def compact_join(list, joiner) do
    list
    |> Euclid.Extra.Enum.compact()
    |> Enum.join(joiner)
    |> Euclid.Exists.presence()
  end

  def initials(<<a::binary-size(1), _::binary>>, <<b::binary-size(1), _::binary>>), do: a <> b
  def initials(_, _), do: nil
end
