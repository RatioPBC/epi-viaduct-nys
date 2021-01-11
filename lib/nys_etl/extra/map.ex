defmodule NYSETL.Extra.Map do
  @moduledoc """
  Extra shared functions for interacting with `Map` data structures.
  """

  alias Euclid.Exists

  @doc """
  Merge map b into map a, where only values in map a that are not
  nil or empty take precedence over values from map b.

  ## Examples

      iex> import NYSETL.Extra.Map
      iex> %{a: 1} |> merge_empty_fields(%{a: 2})
      %{a: 1}
      iex> %{a: 1} |> merge_empty_fields(%{b: 2})
      %{a: 1, b: 2}
      iex> %{a: 1, b: nil} |> merge_empty_fields(%{b: 2})
      %{a: 1, b: 2}
      iex> %{a: 1, b: ""} |> merge_empty_fields(%{b: 2})
      %{a: 1, b: 2}

  """
  @spec merge_empty_fields(map(), map()) :: map()
  def merge_empty_fields(a, b) when is_map(a) and is_map(b) do
    a
    |> Map.merge(b, fn _, left, right ->
      (Exists.present?(left) && left) || right
    end)
  end
end
