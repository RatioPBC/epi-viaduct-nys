defmodule NYSETL.FormatTest do
  use NYSETL.SimpleCase, async: true
  alias NYSETL.Format

  describe "nil" do
    test "formats as empty string" do
      nil |> Format.format() |> assert_eq("")
    end
  end

  describe "Date" do
    test "formats as ddMMMYYYY" do
      ~D[2017-01-05] |> Format.format() |> assert_eq("2017-01-05")
      ~D[2000-02-25] |> Format.format() |> assert_eq("2000-02-25")
    end
  end

  describe "DateTime" do
    test "formats as ddMMMYYYY in New York time" do
      ~U[2017-01-05 01:00:00Z] |> Format.format() |> assert_eq("2017-01-04")
      ~U[2000-02-25 12:00:00Z] |> Format.format() |> assert_eq("2000-02-25")
    end
  end

  describe "Integer" do
    test "formats as a string" do
      6 |> Format.format() |> assert_eq("6")
    end

    test "pads with 0s" do
      6 |> Format.format(pad: 2) |> assert_eq("06")
    end
  end
end
