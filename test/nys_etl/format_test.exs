defmodule NYSETL.FormatTest do
  use NYSETL.SimpleCase, async: true
  alias NYSETL.Format

  describe "nil" do
    test "formats as empty string" do
      nil |> Format.format() |> assert_eq("")
    end
  end

  describe "format/2" do
    test "formats Date as ddMMMYYYY" do
      ~D[2017-01-05] |> Format.format() |> assert_eq("2017-01-05")
      ~D[2000-02-25] |> Format.format() |> assert_eq("2000-02-25")
    end

    test "formats DateTime as ddMMMYYYY in New York time" do
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

  describe "us_phone_number" do
    test "10 digits" do
      assert Format.us_phone_number("2131234567") == "12131234567"
    end

    test "11 digits" do
      assert Format.us_phone_number("92131234567") == "92131234567"
    end

    test "9 digits" do
      assert Format.us_phone_number("131234567") == "131234567"
    end
  end
end
