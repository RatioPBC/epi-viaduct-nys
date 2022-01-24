defmodule NYSETL.Test.TestHelpers do
  import Euclid.Assertions

  alias NYSETL.Repo

  def assert_events(schema, expected_event_names) do
    schema
    |> Repo.preload(:events)
    |> Map.get(:events)
    |> Euclid.Enum.pluck(:type)
    |> assert_eq(expected_event_names)
  end
end
