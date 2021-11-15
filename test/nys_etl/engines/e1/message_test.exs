defmodule NYSETL.Engines.E1.MessageTest do
  use NYSETL.SimpleCase, async: true

  alias NYSETL.Engines.E1.Message

  describe "normalize_phone" do
    test "passes through nils" do
      nil |> Message.normalize_phone() |> assert_eq(nil)
    end

    test "removes non-numeric characters" do
      "(555) 123-4567" |> Message.normalize_phone() |> assert_eq("5551234567")
      "111-123-4567" |> Message.normalize_phone() |> assert_eq("1111234567")
    end
  end

  describe "to_utc_datetime" do
    test "parses ECLRS format in Eastern Time to UTC DateTime" do
      "20MAR2020:06:03:36.589000"
      |> Message.to_utc_datetime()
      |> assert_eq(~U[2020-03-20 10:03:36.589Z])
    end

    test "parses dates that fall on the daylight savings time hour" do
      "07NOV2021:01:19:00.000000"
      |> Message.to_utc_datetime()
      |> assert_eq(~U[2021-11-07 06:19:00.000000Z])
    end
  end

  describe "to_date" do
    test "parses ECLRS format to Date" do
      "20MAR2020:10:03:36.589000"
      |> Message.to_date()
      |> assert_eq(~D[2020-03-20])
    end
  end
end
