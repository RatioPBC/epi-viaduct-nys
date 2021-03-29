defmodule NYSETL.ECLRS.File do
  use Magritte
  use NYSETL, :schema

  defmodule HeaderError do
    defexception [:message]
  end

  NimbleCSV.define(ECLRSParser, separator: "|")

  @header_v1 "PIDLASTNAME|PIDMIDDLENAME|PIDFIRSTNAME|PIDDATEOFBIRTH|PIDSEXCODE|PIDADDRESSLINE1|PIDADDRESSLINE2|PIDCITY|PIDZIPCODE|PIDCOUNTYCODE|PIDHOMEPHONE|MSHLABPFI|MSHSENDINGFACILITYCLIA|MSHSENDINGFACILITYNAME|PIDPATIENTKEY|ZLRFACILITYADDRESSLINE1|ZLRFACILITYADDRESSLINE2|ZLRFACILITYCITY|ZLRFACILITYCODE|ZLRFACILITYNAME|ZLRFACILITYPHONE|ZLRPROVIDERADDRESSLINE1|ZLRPROVIDERCITY|OBRPROVIDERID|OBRPROVIDERFIRSTNAME|OBRPROVIDERLASTNAME|OBRCOLLECTIONDATE|OBRCREATEDATE|OBXLOCALTESTCODE|OBXLOCALTESTDESC|OBXLOINCCODE|OBXLOINCDESC|OBXOBSERVATIONDATE|OBXOBSERVATIONRESULTTEXT|OBXOBSERVATIONRESULTTEXTSHORT|OBXRESULTSTATUSCODE|OBXPRODUCERLABNAME|OBXSNOMEDCODE|OBXSNOMEDDESC|OBRACCESSIONNUM|OBXANALYSISDATE|OBRSPECIMENSOURCENAME|MSHMESSAGEMASTERKEY|PIDUPDATEDATE|RESULTPOSITIVE"
  @header_v1_names String.split(@header_v1, "|")
  @header_v2 "PIDLASTNAME|PIDMIDDLENAME|PIDFIRSTNAME|PIDDATEOFBIRTH|PIDSEXCODE|PIDADDRESSLINE1|PIDADDRESSLINE2|PIDCITY|PIDZIPCODE|PIDCOUNTYCODE|PIDHOMEPHONE|MSHLABPFI|MSHSENDINGFACILITYCLIA|MSHSENDINGFACILITYNAME|PIDPATIENTKEY|ZLRFACILITYADDRESSLINE1|ZLRFACILITYADDRESSLINE2|ZLRFACILITYCITY|ZLRFACILITYCODE|ZLRFACILITYNAME|ZLRFACILITYPHONE|ZLRPROVIDERADDRESSLINE1|ZLRPROVIDERCITY|OBRPROVIDERID|OBRPROVIDERFIRSTNAME|OBRPROVIDERLASTNAME|OBRCOLLECTIONDATE|OBRCREATEDATE|OBXLOCALTESTCODE|OBXLOCALTESTDESC|OBXLOINCCODE|OBXLOINCDESC|OBXOBSERVATIONDATE|OBXOBSERVATIONRESULTTEXT|OBXOBSERVATIONRESULTTEXTSHORT|OBXRESULTSTATUSCODE|OBXPRODUCERLABNAME|OBXSNOMEDCODE|OBXSNOMEDDESC|OBRACCESSIONNUM|OBXANALYSISDATE|OBRSPECIMENSOURCENAME|MSHMESSAGEMASTERKEY|PIDUPDATEDATE|PIDEMPLOYERNAME|PIDEMPLOYERADDRESS|PIDEMPLOYERPHONE|PIDEMPLOYERPHONEALT|PIDEMPLOYEENUMBER|PIDEMPLOYEEJOBTITLE|PIDSCHOOLNAME|PIDSCHOOLDISTRICT|PIDSCHOOLCODE|PIDSCHOOLJOBCLASS|PIDSCHOOLPRESENT|RESULTPOSITIVE"
  @header_v2_names String.split(@header_v2, "|")
  @header_v3 "PIDLASTNAME|PIDMIDDLENAME|PIDFIRSTNAME|PIDDATEOFBIRTH|PIDSEXCODE|PIDADDRESSLINE1|PIDADDRESSLINE2|PIDCITY|PIDZIPCODE|PIDCOUNTYCODE|PIDHOMEPHONE|MSHLABPFI|MSHSENDINGFACILITYCLIA|MSHSENDINGFACILITYNAME|PIDPATIENTKEY|ZLRFACILITYADDRESSLINE1|ZLRFACILITYADDRESSLINE2|ZLRFACILITYCITY|ZLRFACILITYCODE|ZLRFACILITYNAME|ZLRFACILITYPHONE|ZLRPROVIDERADDRESSLINE1|ZLRPROVIDERCITY|OBRPROVIDERID|OBRPROVIDERFIRSTNAME|OBRPROVIDERLASTNAME|OBRCOLLECTIONDATE|OBRCREATEDATE|OBXLOCALTESTCODE|OBXLOCALTESTDESC|OBXLOINCCODE|OBXLOINCDESC|OBXOBSERVATIONDATE|OBXOBSERVATIONRESULTTEXT|OBXOBSERVATIONRESULTTEXTSHORT|OBXRESULTSTATUSCODE|OBXPRODUCERLABNAME|OBXSNOMEDCODE|OBXSNOMEDDESC|OBRACCESSIONNUM|OBXANALYSISDATE|OBRSPECIMENSOURCENAME|MSHMESSAGEMASTERKEY|PIDUPDATEDATE|PIDEMPLOYERNAME|PIDEMPLOYERADDRESS|PIDEMPLOYERPHONE|PIDEMPLOYERPHONEALT|PIDEMPLOYEENUMBER|PIDEMPLOYEEJOBTITLE|PIDSCHOOLNAME|PIDSCHOOLDISTRICT|PIDSCHOOLCODE|PIDSCHOOLJOBCLASS|PIDSCHOOLPRESENT|PIDFIRSTTESTYN|PIDAOEDATE|PIDHEALTHEMPLOYEDYN|PIDCOVIDSYMPTOMATICYN|PIDCOVIDDATEOFONSET|PIDHOSPITALIZEDYN|PIDICUYN|PIDCONGREGATECAREYN|PIDPREGNANCYIND|RESULTPOSITIVE"
  @header_v3_names String.split(@header_v3, "|")

  @v1_to_v2_pad_amount length(@header_v2_names) - length(@header_v1_names)
  @v1_to_v3_pad_amount length(@header_v3_names) - length(@header_v1_names)
  @v2_to_v3_pad_amount length(@header_v3_names) - length(@header_v2_names)

  schema "files" do
    field :filename, :string
    field :processing_started_at, :utc_datetime_usec
    field :processing_completed_at, :utc_datetime_usec
    field :statistics, :map
    field :eclrs_version, :integer
    field :tid, :string
    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    struct
    |> cast(attrs, [:filename, :processing_started_at, :processing_completed_at, :statistics, :eclrs_version, :tid])
    |> validate_required(:filename)
  end

  def file_header(:v1), do: @header_v1
  def file_header(:v2), do: @header_v2
  def file_header(:v3), do: @header_v3

  def file_headers(@header_v1), do: {:v1, @header_v1_names}
  def file_headers(@header_v2), do: {:v2, @header_v2_names}
  def file_headers(@header_v3), do: {:v3, @header_v3_names}
  def file_headers(other), do: raise(HeaderError, message: "Unexpected header, got: #{inspect(other)}")

  def header_names(:v1), do: @header_v1_names
  def header_names(:v2), do: @header_v2_names
  def header_names(:v3), do: @header_v3_names
  def header_names(eclrs_version: 1), do: @header_v1_names
  def header_names(eclrs_version: 2), do: @header_v2_names
  def header_names(eclrs_version: 3), do: @header_v3_names

  def pad_fields(fields, :v1, :v2), do: pad_fields(fields, @v1_to_v2_pad_amount)
  def pad_fields(fields, :v1, :v3), do: pad_fields(fields, @v1_to_v3_pad_amount)
  def pad_fields(fields, :v2, :v3), do: pad_fields(fields, @v2_to_v3_pad_amount)

  def parse_row(row, %__MODULE__{eclrs_version: eclrs_version}) do
    [fields] = ECLRSParser.parse_string(row, skip_headers: false)

    fields_length = length(fields)
    header_length = length(header_names(eclrs_version: eclrs_version))

    if fields_length == header_length do
      {:ok, fields}
    else
      {:error, "ECLRS file v#{eclrs_version} has #{header_length} fields, but row has #{fields_length} fields"}
    end
  end

  def truncate_fields_to_version(fields, :v1), do: truncate_fields(fields, 44)
  def truncate_fields_to_version(fields, :v2), do: truncate_fields(fields, 55)

  def version_number(version), do: Map.fetch!(%{v1: 1, v2: 2}, version)

  defp pad_fields(fields, count) do
    {last, head} = List.pop_at(fields, -1)
    head
    |> Enum.concat(List.duplicate("", count))
    |> Enum.concat([last])
  end

  defp truncate_fields(fields, num_to_keep) do
    {fields_to_keep, tail} = Enum.split(fields, num_to_keep)
    last = Enum.at(tail, -1)
    fields_to_keep
    |> Enum.concat([last])
  end
end
