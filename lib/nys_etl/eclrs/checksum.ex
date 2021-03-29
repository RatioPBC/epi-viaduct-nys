defmodule NYSETL.ECLRS.Checksum do
  alias NYSETL.Crypto
  alias NYSETL.ECLRS.File

  def checksums(row, %File{} = file) when is_binary(row) do
    {:ok, fields} = File.parse_row(row, file)
    checksums(fields, file)
  end

  def checksums(fields, %File{} = file) when is_list(fields) do
    %{
      v1: checksum(fields, file, :v1),
      v2: checksum(fields, file, :v2),
      v3: checksum(fields, file, :v3)
    }
  end

  def checksum(row, %File{} = file, version) when is_binary(row) do
    {:ok, fields} = File.parse_row(row, file)
    checksum(fields, file, version)
  end

  def checksum(fields, %File{eclrs_version: 1}, :v1) do
    fields
    |> checksum_fields()
  end

  def checksum(fields, %File{eclrs_version: 2}, :v1) do
    fields
    |> File.truncate_fields_to_version(:v1)
    |> checksum_fields()
  end

  def checksum(fields, %File{eclrs_version: 3}, :v1) do
    fields
    |> File.truncate_fields_to_version(:v1)
    |> checksum_fields()
  end

  def checksum(fields, %File{eclrs_version: 1}, :v2) do
    fields
    |> File.pad_fields(:v1, :v2)
    |> checksum_fields()
  end

  def checksum(fields, %File{eclrs_version: 2}, :v2) do
    fields
    |> checksum_fields()
  end

  def checksum(fields, %File{eclrs_version: 3}, :v2) do
    fields
    |> File.truncate_fields_to_version(:v2)
    |> checksum_fields()
  end

  def checksum(fields, %File{eclrs_version: 1}, :v3) do
    fields
    |> File.pad_fields(:v1, :v3)
    |> checksum_fields()
  end

  def checksum(fields, %File{eclrs_version: 2}, :v3) do
    fields
    |> File.pad_fields(:v2, :v3)
    |> checksum_fields()
  end

  def checksum(fields, %File{eclrs_version: 3}, :v3) do
    fields
    |> checksum_fields()
  end

  defp checksum_fields(fields) do
    with [dumped_fields] <- ECLRSParser.dump_to_iodata([fields]) do
      dumped_fields
      |> remove_last_element()
      |> IO.iodata_to_binary()
      |> Crypto.sha256()
    end
  end

  defp remove_last_element(list) do
    # supposedly fastest way to remove last element, in this case an unnecessary \n
    list
    |> Enum.reverse()
    |> tl()
    |> Enum.reverse()
  end
end
