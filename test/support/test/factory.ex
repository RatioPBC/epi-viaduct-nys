defmodule NYSETL.Test.Factory do
  def lab_result(index_case, attrs \\ []) do
    defaults = %{accession_number: Euclid.Random.integer() |> to_string(), data: %{}, index_case_id: index_case.id}
    defaults |> Euclid.Map.merge(attrs)
  end

  def person(attrs \\ []),
    do:
      attrs
      |> Enum.into(%{})

  def file_attrs(attrs \\ []),
    do:
      attrs
      |> Enum.into(%{
        filename: "test/fixtures/eclrs/new_records.txt"
      })

  def test_result_attrs(attrs \\ []),
    do:
      attrs
      |> Enum.into(%{})
end
