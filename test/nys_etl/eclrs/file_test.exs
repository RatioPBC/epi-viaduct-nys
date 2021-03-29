defmodule NYSETL.ECLRS.FileTest do
  use NYSETL.DataCase, async: true

  alias NYSETL.ECLRS.File

  describe "changeset" do
    setup do
      attrs = %{
        filename: "path/to/file",
        processing_started_at: DateTime.utc_now(),
        processing_completed_at: DateTime.utc_now(),
        statistics: %{}
      }

      [attrs: attrs]
    end

    test "validates filename presence", context do
      {:error, changeset} =
        %File{}
        |> File.changeset(Map.drop(context.attrs, [:filename]))
        |> Repo.insert()

      assert %{filename: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "parse_row" do
    setup do
      [
        v1_row: "LASTNAME||FIRSTNAME|01MAR1947:00:00:00.000000|M|123 MAIN St||||1111|(555) 123-4567|3130|31D0652945|ACME LABORATORIES INC|15200000000000|321 Main Street||New Rochelle||NEW YORK STATE||321 Main Street|New Rochelle||Sally|Testuser|18MAR2020:00:00:00.000000|20MAR2020:06:03:36.589000|TH68-0|COVID-19 Nasopharynx|94309-2|2019-nCoV RNA XXX NAA+probe-Imp|19MAR2020:19:20:00.000000|Positive for 2019-nCoV|Positive for 2019-nCoV|F||10828004|Positive for 2019-nCoV|102695116|19MAR2020:19:20:00.000000|NASOPHARYNX|15200070260000|14MAY2020:13:43:16.000000|POSITIVE"
      ]
    end

    test "returns :ok and fields when the line and header length match", context do
      {:ok, fields} = File.parse_row(context.v1_row, %File{eclrs_version: 1})
      assert is_list(fields)
    end

    test "returns an error when the line and header length don't match", context do
      {:error, reason} = File.parse_row(context.v1_row, %File{eclrs_version: 2})
      assert String.match?(reason, ~r/ECLRS file v2 has \d+ fields, but row has \d+ fields/)
    end
  end

  describe "truncate_fields_to_version" do
    test "turns the v2 header list into the v1 header list" do
      v2_headers = File.file_header(:v2) |> File.file_headers() |> elem(1)
      v1_headers = File.file_header(:v1) |> File.file_headers() |> elem(1)
      assert File.truncate_fields_to_version(v2_headers, :v1) == v1_headers
    end

    test "turns the v3 header list into the v1 header list" do
      v3_headers = File.file_header(:v3) |> File.file_headers() |> elem(1)
      v1_headers = File.file_header(:v1) |> File.file_headers() |> elem(1)
      assert File.truncate_fields_to_version(v3_headers, :v1) == v1_headers
    end

    test "turns the v3 header list into the v2 header list" do
      v3_headers = File.file_header(:v3) |> File.file_headers() |> elem(1)
      v2_headers = File.file_header(:v2) |> File.file_headers() |> elem(1)
      assert File.truncate_fields_to_version(v3_headers, :v2) == v2_headers
    end
  end
end
