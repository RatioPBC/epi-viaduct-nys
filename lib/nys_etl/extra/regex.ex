defmodule NYSETL.Extra.Regex do
  @moduledoc """
  Reusable regular expressions that can be used to match on specific types of values.
  """

  @uuid ~r"^\b[0-9a-f]{8}\b-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-\b[0-9a-f]{12}\b$"

  @doc """
  A regular expression for matching on UUIDs.

  ## Examples

      iex> "abcdef" =~ NYSETL.Extra.Regex.uuid()
      false

      iex> "4d47af88-4ff0-48f0-831e-50cf23bc9fd2" =~ NYSETL.Extra.Regex.uuid()
      true
  """
  def uuid(), do: @uuid
end
