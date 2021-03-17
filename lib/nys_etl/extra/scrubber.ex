defmodule NYSETL.Extra.Scrubber do
  use Magritte

  @moduledoc """
  Functions to scrub all PII in ECLRS dump files so that it can be used in development.
  Sensitive data is replaced with random strings of the same length and format (letters
  for letters, digits for digits and dates for dates).  Currently only works with the
  45-column ECLRS files but can easily be extended.

  To use, run

      alias NYSETL.Extra.Scrubber
      Scrubber.scrub_file("../eclrs/data/c201012_0932.txt", "./scrubbed.txt")

  Some internal functions have been left public for your pleasure.
  """

  @doc """
  Make a copy of the input file with all sensitive data replaced with random data of the
  same type and length.

  Uses ETS to make sure that a given source string is consistently replaced with the same
  scrubbed string.  The caller can supply an existing ETS for testing purposes or similar.

      Scrubber.scrub_file("../eclrs/data/c201012_0932.txt", "./scrubbed.txt")
  """
  def scrub_file(input_path, output_path, ets \\ :ets.new(:scrubber, [:public])) do
    input_file = File.open!(input_path, [:read])
    {version, header} = version_and_header_from(input_file)
    output_file = File.open!(output_path, [:write])
    IO.puts(output_file, header)

    row_count =
      IO.read(input_file, :all)
      |> String.split(~r/\r*\n+/, trim: true)
      |> Flow.from_enumerable()
      |> Flow.map(fn row -> scrub_row({version, row}, ets) end)
      |> Flow.reduce(
        fn -> [] end,
        fn row, ack ->
          IO.puts(output_file, row)
          [true | ack]
        end
      )
      |> Enum.count()

    :ok = File.close(output_file)
    {:ok, row_count}
  end

  defp version_and_header_from(input_file) do
    header =
      input_file
      |> IO.read(:line)
      |> String.trim()

    {version, _headers} =
      header
      |> NYSETL.ECLRS.File.file_headers()

    {version, header}
  end

  @doc ~S"""
  Scrub all PII fields in one row.

  ## Examples

      iex> import NYSETL.Extra.Scrubber
      iex> ets = :ets.new(:scrubber, [:public])
      iex> :rand.seed(:exsss, {101, 102, 103})
      iex> scrub_row({:v1, "Doe|J|John|18MAR1965:00:00:00|||||||||||||||||||||||||||||||||||||||||unclear\n"}, ets)
      "XTK|K|RDFE|28AUG2018:00:00:00|||||||||||||||||||||||||||||||||||||||||unclear\n"
      iex> scrub_row({:v1, "Doe|A|Mary|23MAY1965:00:00:00.000000|||||||||||||||||||||||||||||||||||||||||POS"}, ets)
      "XTK|Z|BYLL|18APR2016:00:00:00.000000|||||||||||||||||||||||||||||||||||||||||POS"
  """
  def scrub_row({version, row}, ets) do
    row
    |> String.split("|")
    |> Enum.with_index()
    |> Enum.map(&scrub_if_index_should_be_scrubbed(version, &1, ets))
    |> Enum.join("|")
  end

  @v1_public %{
               "PIDSEXCODE" => 4,
               "PIDZIPCODE" => 8,
               "PIDCOUNTYCODE" => 9,
               "MSHLABPFI" => 11,
               "MSHSENDINGFACILITYCLIA" => 12,
               "MSHSENDINGFACILITYNAME" => 13,
               "PIDPATIENTKEY" => 14,
               "ZLRFACILITYCODE" => 18,
               "ZLRFACILITYNAME" => 19,
               "OBRPROVIDERID" => 23,
               "OBRPROVIDERFIRSTNAME" => 24,
               "OBRPROVIDERLASTNAME" => 25,
               "OBRCOLLECTIONDATE" => 26,
               "OBRCREATEDATE" => 27,
               "OBXLOCALTESTCODE" => 28,
               "OBXLOCALTESTDESC" => 29,
               "OBXLOINCCODE" => 30,
               "OBXLOINCDESC" => 31,
               "OBXOBSERVATIONDATE" => 32,
               "OBXOBSERVATIONRESULTTEXT" => 33,
               "OBXOBSERVATIONRESULTTEXTSHORT" => 34,
               "OBXRESULTSTATUSCODE" => 35,
               "OBXPRODUCERLABNAME" => 36,
               "OBXSNOMEDCODE" => 37,
               "OBXSNOMEDDESC" => 38,
               "OBRACCESSIONNUM" => 39,
               "OBXANALYSISDATE" => 40,
               "OBRSPECIMENSOURCENAME" => 41,
               "MSHMESSAGEMASTERKEY" => 42,
               "PIDUPDATEDATE" => 43,
               "RESULTPOSITIVE" => 44
             }
             |> Map.values()

  @doc """
  Scrubs a string if its field index requires scrubbing the specified column layout.

  ## Examples
      iex> import NYSETL.Extra.Scrubber
      iex> ets = :ets.new(:scrubber, [:public])
      iex> :rand.seed(:exsss, {101, 102, 103})
      iex> scrub_if_index_should_be_scrubbed(:v1, {"Doe", 0}, ets)
      "XTK"
      iex> scrub_if_index_should_be_scrubbed(:v1, {"59483", 8}, ets) # ZIP is not PII
      "59483"
  """
  def scrub_if_index_should_be_scrubbed(:v1, {string, ix}, _ets) when ix in @v1_public, do: string
  def scrub_if_index_should_be_scrubbed(:v1, {string, _ix}, ets), do: scrub_and_remember(string, ets)

  @doc """
  Return a string which is based on the input string but with all letters replaced
  with random uppercase letters and all digits replaced with random digits.
  Uses ETS to always return the same output for a certain input.

  ## Examples

      iex> import NYSETL.Extra.Scrubber
      iex> ets = :ets.new(:scrubber, [:public])
      iex> :rand.seed(:exsss, {101, 102, 103})
      iex> scrub_and_remember("john doe", ets)
      "XTKK RDF"
      iex> scrub_and_remember("mary-ann doe", ets)
      "EWZB-YLL ZCH"
      iex> scrub_and_remember("john doe", ets)
      "XTKK RDF"
  """
  def scrub_and_remember(string, ets) do
    case :ets.lookup(ets, string) do
      [{_, scrubbed}] ->
        scrubbed

      [] ->
        scrubbed = scrub_random(string)

        case :ets.insert_new(ets, {string, scrubbed}) do
          false ->
            IO.inspect(string, label: "race condition averted")
            [{_, scrubbed}] = :ets.lookup(ets, string)
            scrubbed

          _ ->
            scrubbed
        end
    end
  end

  @doc """
  Return a string which is based on the input string but with all letters replaced
  with random uppercase letters and all digits replaced with random digits.
  Replaces valid ISO dates with valid ISO dates.

  ## Examples

      iex> import NYSETL.Extra.Scrubber
      iex> :rand.seed(:exsss, {101, 102, 103})
      iex> scrub_random("john doe")
      "XTKK RDF"
      iex> scrub_random("john doe") # no memory
      "EWZB YLL"
      iex> scrub_random("123 West 27th St.")
      "432 ZCHT 39OA QS."
      iex> scrub_random("23MAY1965") # special handling of dates
      "17FEB1945"
      iex> scrub_random("23MAY1965:00:00:00.000000") # special handling of datetimes
      "29NOV1994:00:00:00.000000"
  """
  def scrub_random(string) do
    case looks_like_a_date?(string) do
      [_all, time] ->
        random_date(time)

      nil ->
        string
        |> Regex.replace(~r/[[:alpha:]]/, ..., &random_letter/1)
        |> Regex.replace(~r/[[:digit:]]/, ..., &random_digit/1)
    end
  end

  defp looks_like_a_date?(string) do
    Regex.run(~r/^\d{2}(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)\d{4}((?::\d{2}:\d{2}:\d{2}(?:\.\d+)?)?)$/, string)
  end

  @days_in_span Date.diff(~D[2020-06-01], ~D[1900-01-01])
  def random_date(time) do
    Date.add(~D[1900-01-01], :rand.uniform(@days_in_span))
    |> Timex.format!("{0D}{Mshort}{YYYY}#{time}")
    |> String.upcase()
  end

  @letters String.codepoints("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
  defp random_letter(_) do
    Enum.random(@letters)
  end

  @digits String.codepoints("1234567890")
  defp random_digit(_) do
    Enum.random(@digits)
  end
end
