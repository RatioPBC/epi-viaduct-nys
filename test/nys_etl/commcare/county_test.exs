defmodule NYSETL.Commcare.CountyTest do
  use NYSETL.DataCase, async: true

  setup :mock_county_list

  alias NYSETL.Commcare.County

  describe "get" do
    test "gets the county from config override" do
      County.get(fips: "1111")
      |> assert_eq(
        {:ok,
         %County{
           display: "Midsomer",
           domain: "uk-midsomer-cdcms",
           fips: "1111",
           gaz: "ms-gaz",
           location_id: "a1a1a1a1a1",
           name: "midsomer"
         }}
      )

      County.get(name: "midsomer")
      |> assert_eq(
        {:ok,
         %County{
           display: "Midsomer",
           domain: "uk-midsomer-cdcms",
           fips: "1111",
           gaz: "ms-gaz",
           location_id: "a1a1a1a1a1",
           name: "midsomer"
         }}
      )

      County.get(domain: "uk-midsomer-cdcms")
      |> assert_eq(
        {:ok,
         %County{
           display: "Midsomer",
           domain: "uk-midsomer-cdcms",
           fips: "1111",
           gaz: "ms-gaz",
           location_id: "a1a1a1a1a1",
           name: "midsomer"
         }}
      )

      County.get(fips: "7")
      |> assert_eq({:error, "no county found with FIPS code '7'"})
    end

    test "gets the county details given a county fips" do
      County.get([fips: "7"], from_api: true)
      |> assert_eq(
        {:ok,
         %County{
           display: "Broome",
           domain: "ny-broome-cdcms",
           fips: "7",
           gaz: "3",
           location_id: "1a21c1a2babb4b81b079484499b36435",
           name: "broome"
         }}
      )
    end

    test "gets the county details given a county fips integer" do
      County.get([fips: 7], from_api: true)
      |> assert_eq(
        {:ok,
         %County{
           display: "Broome",
           domain: "ny-broome-cdcms",
           fips: "7",
           gaz: "3",
           location_id: "1a21c1a2babb4b81b079484499b36435",
           name: "broome"
         }}
      )
    end

    test "gets the county by name" do
      County.get([name: "columbia"], from_api: true)
      |> assert_ok()
      |> assert_eq(%County{
        display: "Columbia",
        domain: "ny-columbia-cdcms",
        fips: "21",
        gaz: "10",
        location_id: "e4a8a57d98db487aadb28c7037539a3d",
        name: "columbia"
      })
    end

    test "gets the county by location_id" do
      County.get([location_id: "e4a8a57d98db487aadb28c7037539a3d"], from_api: true)
      |> assert_ok()
      |> assert_eq(%County{
        display: "Columbia",
        domain: "ny-columbia-cdcms",
        fips: "21",
        gaz: "10",
        location_id: "e4a8a57d98db487aadb28c7037539a3d",
        name: "columbia"
      })
    end

    test ":not_participating if the county is not participating" do
      County.get([fips: "5"], from_api: true)
      |> assert_eq({
        :non_participating,
        %NYSETL.Commcare.County{display: "Bronx", domain: "", fips: "5", gaz: "94", location_id: "", name: "bronx"}
      })
    end

    test ":not_participating if the county is a special DOH parking code" do
      County.get([fips: "905"], from_api: true)
      |> assert_eq({
        :non_participating,
        %NYSETL.Commcare.County{display: "DOH special 905 -- county assign, manual (address missing)", fips: "905"}
      })
    end

    test ":error if county fips is not found" do
      County.get([fips: "glorp"], from_api: true)
      |> assert_eq({:error, "no county found with FIPS code 'glorp'"})
    end
  end

  describe "participating_counties" do
    test "returns list of counties where is_participating=yes" do
      County.participating_counties()
      |> Extra.Enum.pluck(:domain)
      |> assert_eq(~w{
        uk-statewide-cdcms
        sw-yggdrasil-cdcms
        uk-midsomer-cdcms
      })

      domains =
        County.participating_counties(from_api: true)
        |> Extra.Enum.pluck(:domain)

      assert Enum.member?(domains, "ny-rensselaer-cdcms")
    end
  end

  describe "statewide" do
    test "returns {:ok, county} with the is_statewide=yes county" do
      County.statewide_county()
      |> assert_ok()
      |> assert_eq(%County{
        display: "UK Statewide",
        domain: "uk-statewide-cdcms",
        fips: "1234",
        gaz: "state-gaz",
        location_id: "statewide-owner-id",
        name: "statewide"
      })

      County.statewide_county(from_api: true)
      |> assert_ok()
      |> assert_eq(%County{
        display: "NY Statewide",
        domain: "ny-statewide-cdcms",
        fips: "900",
        gaz: "",
        location_id: "cf9775b751794693b56843f0432d3bec",
        name: "ny_statewide"
      })
    end
  end
end
