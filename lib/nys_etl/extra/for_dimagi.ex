defmodule NYSETL.Extra.ForDimagi do
  use Magritte
  import Ecto.Query
  alias NYSETL.Commcare.Api
  alias NYSETL.Engines.E1.FileReader
  alias NYSETL.Engines.E1.Message

  def recent_from_server(output_path, limit \\ 100) do
    all =
      from(
        tr in NYSETL.ECLRS.TestResult,
        order_by: [desc: tr.file_id, desc: tr.id],
        limit: ^limit,
        select: [tr.raw_data]
      )
      |> NYSETL.Repo.all()
      |> Enum.map(&Kernel.hd/1)

    tmp_path = Briefly.create!()
    header = Message.file_header(:v1)
    File.write!(tmp_path, [header | all] |> Enum.map(fn s -> s <> "\n" end))
    NYSETL.Extra.Scrubber.scrub_file(tmp_path, output_path)
    File.rm!(tmp_path)
  end

  def one_file_for_all(case_ids, input_path, output_path) do
    cases = get_cases(case_ids)
    eclrs_maps = get_eclrs_maps(input_path, length(cases))

    out = File.open!(output_path, [:write])
    IO.write(out, Message.file_header(:v1) <> "\n")

    Enum.zip(cases, eclrs_maps)
    |> Enum.with_index(DateTime.utc_now() |> DateTime.to_unix(:microsecond))
    |> Enum.each(fn {dimagi_eclrs, patient_key} ->
      merge(dimagi_eclrs, patient_key)
      |> inline()
      |> IO.write(out, ...)
    end)
  end

  def one_file_for_each(case_ids, input_path, output_dir) do
    cases = get_cases(case_ids)
    eclrs_maps = get_eclrs_maps(input_path, length(cases))

    Enum.zip(cases, eclrs_maps)
    |> Enum.with_index(DateTime.utc_now() |> DateTime.to_unix(:microsecond))
    |> Enum.each(fn {dimagi_eclrs, patient_key} ->
      name = patient_key |> Integer.to_string() |> Kernel.<>(".csv") |> IO.inspect(label: "writing file")
      out = File.open!(Path.join(output_dir, name), [:write])
      IO.write(out, Message.file_header(:v1) <> "\n")
      merge(dimagi_eclrs, patient_key) |> inline() |> IO.write(out, ...)
      File.close(out)
    end)
  end

  def get_cases(case_ids) do
    case_ids
    |> Enum.map(fn case_id ->
      {:ok, map} = Api.get_case(commcare_case_id: case_id, county_domain: "ny-integrations-cdcms")
      map
    end)
  end

  def get_eclrs_maps(input_path, line_count) do
    {:producer, state} = FileReader.init(%{filename: input_path})
    {:v1, headers} = state.file_headers

    FileReader.read(state, line_count)
    |> Enum.map(fn {:v1, line} -> Enum.zip(headers, String.split(line, "|")) |> Map.new() end)
  end

  # @staging "600"
  @integrations "800"

  def merge({dimagi, eclrs}, patient_key) do
    props = dimagi["properties"]
    {:ok, dob} = Map.get(props, "dob") |> Calendar.ISO.parse_date()

    eclrs
    |> Map.replace!("PIDFIRSTNAME", props["first_name"])
    |> Map.replace!("PIDLASTNAME", props["last_name"])
    |> Map.replace!("PIDMIDDLENAME", "")
    |> Map.replace!("PIDDATEOFBIRTH", dob |> Timex.format!("{0D}{Mshort}{YYYY}:00:00:00.000000") |> String.upcase())
    |> Map.replace!("PIDCOUNTYCODE", @integrations)
    |> Map.replace!("PIDPATIENTKEY", patient_key |> Integer.to_string())
  end

  def inline(eclrs_map) do
    {:v1, headers} = Message.file_headers(Message.file_header(:v1))

    headers
    |> Enum.map(fn key -> eclrs_map[key] end)
    |> Enum.join("|")
    |> Kernel.<>("\n")
  end
end
