defmodule NYSETL.Engines.E1.Message do
  @moduledoc """
  Info about a specific row from an ECLRS file. Generates a checksum for that row, for
  discovering when a row exactly matches something that has already been processed.

  If a row is unique, it represents either a new lab result or an update to an existing
  lab result, and is `parse`'d as a new TestResult record.
  """

  use Magritte
  alias NYSETL.Crypto

  defmodule HeaderError do
    defexception [:message]
  end

  defstruct ~w{
    checksum
    file_id
    raw_data
    version
    fields
  }a

  def new(attrs), do: __struct__(attrs)

  def transform({version, row}, file) do
    {:ok, [fields]} =
      StringIO.open(row, fn pid ->
        pid |> IO.binstream(:line) |> CSV.decode!(separator: ?|) |> Enum.take(1)
      end)

    new(raw_data: row, checksum: checksum(version, row, fields), file_id: file.id, version: version, fields: fields)
  end

  @header_v1 "PIDLASTNAME|PIDMIDDLENAME|PIDFIRSTNAME|PIDDATEOFBIRTH|PIDSEXCODE|PIDADDRESSLINE1|PIDADDRESSLINE2|PIDCITY|PIDZIPCODE|PIDCOUNTYCODE|PIDHOMEPHONE|MSHLABPFI|MSHSENDINGFACILITYCLIA|MSHSENDINGFACILITYNAME|PIDPATIENTKEY|ZLRFACILITYADDRESSLINE1|ZLRFACILITYADDRESSLINE2|ZLRFACILITYCITY|ZLRFACILITYCODE|ZLRFACILITYNAME|ZLRFACILITYPHONE|ZLRPROVIDERADDRESSLINE1|ZLRPROVIDERCITY|OBRPROVIDERID|OBRPROVIDERFIRSTNAME|OBRPROVIDERLASTNAME|OBRCOLLECTIONDATE|OBRCREATEDATE|OBXLOCALTESTCODE|OBXLOCALTESTDESC|OBXLOINCCODE|OBXLOINCDESC|OBXOBSERVATIONDATE|OBXOBSERVATIONRESULTTEXT|OBXOBSERVATIONRESULTTEXTSHORT|OBXRESULTSTATUSCODE|OBXPRODUCERLABNAME|OBXSNOMEDCODE|OBXSNOMEDDESC|OBRACCESSIONNUM|OBXANALYSISDATE|OBRSPECIMENSOURCENAME|MSHMESSAGEMASTERKEY|PIDUPDATEDATE|RESULTPOSITIVE"
  @header_v1_names String.split(@header_v1, "|")
  @header_v2 "PIDLASTNAME|PIDMIDDLENAME|PIDFIRSTNAME|PIDDATEOFBIRTH|PIDSEXCODE|PIDADDRESSLINE1|PIDADDRESSLINE2|PIDCITY|PIDZIPCODE|PIDCOUNTYCODE|PIDHOMEPHONE|MSHLABPFI|MSHSENDINGFACILITYCLIA|MSHSENDINGFACILITYNAME|PIDPATIENTKEY|ZLRFACILITYADDRESSLINE1|ZLRFACILITYADDRESSLINE2|ZLRFACILITYCITY|ZLRFACILITYCODE|ZLRFACILITYNAME|ZLRFACILITYPHONE|ZLRPROVIDERADDRESSLINE1|ZLRPROVIDERCITY|OBRPROVIDERID|OBRPROVIDERFIRSTNAME|OBRPROVIDERLASTNAME|OBRCOLLECTIONDATE|OBRCREATEDATE|OBXLOCALTESTCODE|OBXLOCALTESTDESC|OBXLOINCCODE|OBXLOINCDESC|OBXOBSERVATIONDATE|OBXOBSERVATIONRESULTTEXT|OBXOBSERVATIONRESULTTEXTSHORT|OBXRESULTSTATUSCODE|OBXPRODUCERLABNAME|OBXSNOMEDCODE|OBXSNOMEDDESC|OBRACCESSIONNUM|OBXANALYSISDATE|OBRSPECIMENSOURCENAME|MSHMESSAGEMASTERKEY|PIDUPDATEDATE|PIDEMPLOYERNAME|PIDEMPLOYERADDRESS|PIDEMPLOYERPHONE|PIDEMPLOYERPHONEALT|PIDEMPLOYEENUMBER|PIDEMPLOYEEJOBTITLE|PIDSCHOOLNAME|PIDSCHOOLDISTRICT|PIDSCHOOLCODE|PIDSCHOOLJOBCLASS|PIDSCHOOLPRESENT|RESULTPOSITIVE"
  @header_v2_names String.split(@header_v2, "|")
  @indexes_in_v2_not_in_v1 44..54

  def file_header(:v1), do: @header_v1
  def file_header(:v2), do: @header_v2

  def file_headers(@header_v1), do: {:v1, @header_v1_names}
  def file_headers(@header_v2), do: {:v2, @header_v2_names}
  def file_headers(other), do: raise(HeaderError, message: "Unexpected header, got: #{inspect(other)}")

  def checksum(:v1, row, _fields),
    do: Crypto.sha256(row)

  def checksum(:v2, _row, fields) do
    fields
    |> remove_new_v2_fields()
    |> Enum.join("|")
    |> checksum(:v1, ..., fields)
  end

  def remove_new_v2_fields(fields) do
    fields
    |> Enum.with_index()
    |> Enum.reject(fn
      {_, ix} when ix in @indexes_in_v2_not_in_v1 -> true
      _ -> false
    end)
    |> Enum.map(&elem(&1, 0))
  end

  def parse(%__MODULE__{version: :v1} = message) do
    [
      patient_name_last,
      patient_name_middle,
      patient_name_first,
      patient_dob,
      patient_gender,
      patient_address_1,
      patient_address_2,
      patient_city,
      patient_zip,
      county_fips_code,
      patient_phone_home,
      lab_id,
      sending_facility_clia,
      lab_name,
      patient_key,
      request_facility_address_1,
      request_facility_address_2,
      request_facility_city,
      request_facility_code,
      request_facility_name,
      request_phone_facility,
      request_provider_address_1,
      request_provider_city,
      request_provider_id,
      request_provider_name_first,
      request_provider_name_last,
      request_collection_date,
      obxcreatedate,
      result_local_test_code,
      result_local_test_desc,
      result_loinc_code,
      result_loinc_desc,
      result_observation_date,
      result_observation_text,
      result_observation_text_short,
      result_status_code,
      result_producer_lab_name,
      result_snomed_code,
      result_snomed_desc,
      request_accession_number,
      result_analysis_date,
      request_specimen_source_name,
      message_master_key,
      patient_updated_at,
      result
    ] = message.fields

    %{
      county_id: String.to_integer(county_fips_code),
      eclrs_create_date: to_utc_datetime(obxcreatedate),
      file_id: message.file_id,
      lab_id: lab_id,
      lab_name: lab_name,
      message_master_key: message_master_key,
      patient_address_1: patient_address_1,
      patient_address_2: patient_address_2,
      patient_city: patient_city,
      patient_dob: to_date(patient_dob),
      patient_gender: patient_gender,
      patient_key: patient_key,
      patient_name_first: patient_name_first,
      patient_name_last: patient_name_last,
      patient_name_middle: patient_name_middle,
      patient_phone_home: patient_phone_home,
      patient_phone_home_normalized: normalize_phone(patient_phone_home),
      patient_updated_at: to_utc_datetime(patient_updated_at),
      patient_zip: patient_zip,
      raw_data: message.raw_data,
      request_accession_number: request_accession_number,
      request_collection_date: to_utc_datetime(request_collection_date),
      request_facility_address_1: request_facility_address_1,
      request_facility_address_2: request_facility_address_2,
      request_facility_city: request_facility_city,
      request_facility_code: request_facility_code,
      request_facility_name: request_facility_name,
      request_phone_facility: request_phone_facility,
      request_phone_facility_normalized: normalize_phone(request_phone_facility),
      request_provider_address_1: request_provider_address_1,
      request_provider_city: request_provider_city,
      request_provider_id: request_provider_id,
      request_provider_name_first: request_provider_name_first,
      request_provider_name_last: request_provider_name_last,
      request_specimen_source_name: request_specimen_source_name,
      result: result,
      result_analysis_date: to_utc_datetime(result_analysis_date),
      result_local_test_code: result_local_test_code,
      result_local_test_desc: result_local_test_desc,
      result_loinc_code: result_loinc_code,
      result_loinc_desc: result_loinc_desc,
      result_observation_date: to_utc_datetime(result_observation_date),
      result_observation_text: result_observation_text,
      result_observation_text_short: result_observation_text_short,
      result_producer_lab_name: result_producer_lab_name,
      result_snomed_code: result_snomed_code,
      result_snomed_desc: result_snomed_desc,
      result_status_code: result_status_code,
      sending_facility_clia: sending_facility_clia
    }
  end

  def parse(%__MODULE__{version: :v2} = message) do
    [
      patient_name_last,
      patient_name_middle,
      patient_name_first,
      patient_dob,
      patient_gender,
      patient_address_1,
      patient_address_2,
      patient_city,
      patient_zip,
      county_fips_code,
      patient_phone_home,
      lab_id,
      sending_facility_clia,
      lab_name,
      patient_key,
      request_facility_address_1,
      request_facility_address_2,
      request_facility_city,
      request_facility_code,
      request_facility_name,
      request_phone_facility,
      request_provider_address_1,
      request_provider_city,
      request_provider_id,
      request_provider_name_first,
      request_provider_name_last,
      request_collection_date,
      obxcreatedate,
      result_local_test_code,
      result_local_test_desc,
      result_loinc_code,
      result_loinc_desc,
      result_observation_date,
      result_observation_text,
      result_observation_text_short,
      result_status_code,
      result_producer_lab_name,
      result_snomed_code,
      result_snomed_desc,
      request_accession_number,
      result_analysis_date,
      request_specimen_source_name,
      message_master_key,
      patient_updated_at,
      employer_name,
      employer_address,
      employer_phone,
      employer_phone_alt,
      employee_number,
      employee_job_title,
      school_name,
      school_district,
      school_code,
      school_job_class,
      school_present,
      result
    ] = message.fields

    %{
      county_id: String.to_integer(county_fips_code),
      eclrs_create_date: to_utc_datetime(obxcreatedate),
      employee_job_title: employee_job_title,
      employee_number: employee_number,
      employer_address: employer_address,
      employer_name: employer_name,
      employer_phone: employer_phone,
      employer_phone_alt: employer_phone_alt,
      file_id: message.file_id,
      lab_id: lab_id,
      lab_name: lab_name,
      message_master_key: message_master_key,
      patient_address_1: patient_address_1,
      patient_address_2: patient_address_2,
      patient_city: patient_city,
      patient_dob: to_date(patient_dob),
      patient_gender: patient_gender,
      patient_key: patient_key,
      patient_name_first: patient_name_first,
      patient_name_last: patient_name_last,
      patient_name_middle: patient_name_middle,
      patient_phone_home: patient_phone_home,
      patient_phone_home_normalized: normalize_phone(patient_phone_home),
      patient_updated_at: to_utc_datetime(patient_updated_at),
      patient_zip: patient_zip,
      raw_data: message.raw_data,
      request_accession_number: request_accession_number,
      request_collection_date: to_utc_datetime(request_collection_date),
      request_facility_address_1: request_facility_address_1,
      request_facility_address_2: request_facility_address_2,
      request_facility_city: request_facility_city,
      request_facility_code: request_facility_code,
      request_facility_name: request_facility_name,
      request_phone_facility: request_phone_facility,
      request_phone_facility_normalized: normalize_phone(request_phone_facility),
      request_provider_address_1: request_provider_address_1,
      request_provider_city: request_provider_city,
      request_provider_id: request_provider_id,
      request_provider_name_first: request_provider_name_first,
      request_provider_name_last: request_provider_name_last,
      request_specimen_source_name: request_specimen_source_name,
      result: result,
      result_analysis_date: to_utc_datetime(result_analysis_date),
      result_local_test_code: result_local_test_code,
      result_local_test_desc: result_local_test_desc,
      result_loinc_code: result_loinc_code,
      result_loinc_desc: result_loinc_desc,
      result_observation_date: to_utc_datetime(result_observation_date),
      result_observation_text: result_observation_text,
      result_observation_text_short: result_observation_text_short,
      result_producer_lab_name: result_producer_lab_name,
      result_snomed_code: result_snomed_code,
      result_snomed_desc: result_snomed_desc,
      result_status_code: result_status_code,
      school_code: school_code,
      school_district: school_district,
      school_job_class: school_job_class,
      school_name: school_name,
      school_present: school_present,
      sending_facility_clia: sending_facility_clia
    }
  end

  def normalize_phone(nil), do: nil
  def normalize_phone(string) when is_binary(string), do: string |> String.replace(~r|[^\d]|, "", global: true)

  def to_date(<<day::binary-size(2), month::binary-size(3), year::binary-size(4), _rest::binary>>) do
    "#{day}#{Macro.camelize(String.downcase(month))}#{year}"
    |> Timex.parse("%d%b%Y", :strftime)
    |> case do
      {:ok, datetime} -> datetime |> NaiveDateTime.to_date()
      {:error, _error} -> nil
    end
  end

  def to_date(_), do: nil

  def to_utc_datetime(
        <<day::binary-size(2), month::binary-size(3), year::binary-size(4), ":", hour::binary-size(2), ":", minute::binary-size(2), ":",
          second::binary-size(2), ".", microseconds::binary-size(6), _rest::binary>>
      ) do
    "#{day}#{Macro.camelize(String.downcase(month))}#{year}:#{hour}:#{minute}:#{second}.#{microseconds}"
    |> Timex.parse("%d%b%Y:%H:%M:%S.%f", :strftime)
    |> case do
      {:ok, datetime} -> datetime |> Timex.to_datetime("America/New_York") |> DateTime.shift_zone!("Etc/UTC")
      {:error, _error} -> nil
    end
  end

  def to_utc_datetime(_), do: nil
end
