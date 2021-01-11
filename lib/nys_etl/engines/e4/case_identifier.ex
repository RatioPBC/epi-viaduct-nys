defmodule NYSETL.Engines.E4.CaseIdentifier do
  defstruct ~w{case_id county_domain county_id external_id transfer_source_case_id}a

  alias Euclid.Exists
  alias NYSETL.Commcare
  alias NYSETL.Repo

  def new(data) do
    map_without_empty_values =
      data
      |> Enum.into(%{})
      |> Enum.map(fn {k, v} -> {k, Exists.presence(v)} end)
      |> Map.new()

    struct!(__MODULE__, map_without_empty_values)
  end

  def for_case_id(case_id) do
    index_case = Commcare.IndexCase |> Repo.get_by!(case_id: case_id)
    {:ok, %{domain: domain}} = Commcare.County.get(fips: index_case.county_id)
    new(case_id: case_id, county_domain: domain, county_id: index_case.county_id)
  end

  def describe(%__MODULE__{} = case_identifier) do
    fields_with_values =
      case_identifier
      |> Map.take(~w{case_id county_domain county_id external_id transfer_source_case_id}a)
      |> Enum.reject(fn {_k, v} -> v == nil end)
      |> Enum.map(fn {k, v} -> "#{k}:#{v}" end)

    "<" <> Enum.join(fields_with_values, " ") <> ">"
  end
end
