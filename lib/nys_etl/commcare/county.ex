defmodule NYSETL.Commcare.County do
  alias NYSETL.Commcare

  defstruct ~w(display domain fips gaz location_id name)a

  def get(finder, opts \\ [])

  def get([fips: fips], opts),
    do: get_by("fips", fips, "FIPS code", opts)

  def get([location_id: location_id], opts),
    do: get_by("location_id", location_id, "location_id", opts)

  def get([name: name], opts),
    do: get_by("county_name", name, "county_name", opts)

  def get([domain: domain], opts),
    do: get_by("domain", domain, "domain", opts)

  defp get_by(key, value, key_description, opts) do
    opts
    |> all_counties()
    |> find_commcare_formatted_county_by(key, value)
    |> transform_into_internal_format(key_description, value)
  end

  def all_counties(opts \\ []) do
    opts
    |> Keyword.get(:from_api, Application.get_env(:nys_etl, :use_commcare_county_list))
    |> case do
      false ->
        Application.get_env(:nys_etl, :county_list)

      true ->
        {:ok, county_list, _} = Commcare.Api.get_county_list(Keyword.get(opts, :cache, :refer_to_config))

        county_list
        |> Enum.map(& &1["fields"])
    end
    |> Kernel.++(Application.get_env(:nys_etl, :extra_county_list))
  end

  def participating_counties(opts \\ []) do
    all_counties(opts)
    |> Enum.reduce([], fn
      %{"participating" => "no"}, acc -> acc
      fields, acc -> [transform_into_internal_format!(fields, "participating", "yes") | acc]
    end)
  end

  def statewide_county(opts \\ []) do
    all_counties(opts)
    |> find_commcare_formatted_county_by("is_state_domain", "yes")
    |> transform_into_internal_format("is_state_domain", "yes")
  end

  defp find_commcare_formatted_county_by(list, field, value) when is_integer(value) do
    find_commcare_formatted_county_by(list, field, Integer.to_string(value))
  end

  defp find_commcare_formatted_county_by(county_list, field, value) do
    county_list
    |> Enum.find(&(&1[field] == value))
  end

  defp transform_into_internal_format(nil, key, value), do: {:error, "no county found with #{key} '#{value}'"}

  defp transform_into_internal_format(%{"participating" => "no"} = county_info, _key, _value),
    do: {:non_participating, internal_form_from_info(county_info)}

  defp transform_into_internal_format(county_info, _key, _value), do: {:ok, internal_form_from_info(county_info)}

  defp transform_into_internal_format!(county_info, key, value) do
    transform_into_internal_format(county_info, key, value)
    |> case do
      {:ok, county} -> county
      {:error, error} -> raise error
    end
  end

  defp internal_form_from_info(county_info) do
    %__MODULE__{
      display: county_info["county_display"],
      domain: county_info["domain"],
      fips: county_info["fips"],
      gaz: county_info["gaz"],
      location_id: county_info["location_id"],
      name: county_info["county_name"]
    }
  end
end
