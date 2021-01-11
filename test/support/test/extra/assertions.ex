defmodule NYSETL.Test.Extra.Assertions do
  def assert_ok({:ok, thing}), do: thing

  def assert_ok(thing) do
    ExUnit.Assertions.flunk("""
    Expected an {:ok, thing}, got:
    #{inspect(thing)}
    """)
  end

  def assert_ok(tuple, expected_elem) do
    case tuple do
      {:ok, thing, ^expected_elem} ->
        thing

      _ ->
        ExUnit.Assertions.flunk("""
        Expected an {:ok, thing, #{inspect(expected_elem)}}, got:
        #{inspect(tuple)}
        """)
    end
  end
end
