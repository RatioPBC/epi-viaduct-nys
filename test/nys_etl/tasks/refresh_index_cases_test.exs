defmodule NYSETL.Tasks.RefreshIndexCasesTest do
  use NYSETL.DataCase, async: false
  use Oban.Testing, repo: NYSETL.Repo

  import Ecto.Query

  alias NYSETL.Commcare
  alias NYSETL.Commcare.County
  alias NYSETL.Commcare.IndexCase
  alias NYSETL.ECLRS
  alias NYSETL.Tasks.RefreshIndexCases

  setup :start_supervised_oban

  describe "matching(filter)" do
    test "refreshes index cases matching the filter" do
      filter = where(IndexCase, [ic], ic.case_id == "joe")

      {:ok, midsomer} = County.get(name: "midsomer")
      {:ok, midsomer_county} = ECLRS.find_or_create_county(midsomer.fips)

      {:ok, person1} = Commcare.create_person(%{data: %{}, patient_keys: ["1"], name_first: "Joe", name_last: nil})

      {:ok, _} =
        Commcare.create_index_case(%{
          case_id: "joe",
          data: %{},
          person_id: person1.id,
          county_id: midsomer_county.id
        })

      {:ok, person2} = Commcare.create_person(%{data: %{}, patient_keys: ["2"], name_first: "Not Joe", name_last: nil})

      {:ok, _} =
        Commcare.create_index_case(%{
          case_id: "not-joe",
          data: %{},
          person_id: person2.id,
          county_id: midsomer_county.id
        })

      assert :ok = RefreshIndexCases.matching(filter)

      assert [
               %{
                 worker: "NYSETL.Commcare.CaseImporter",
                 priority: 3,
                 args: %{"commcare_case_id" => "joe", "domain" => "uk-midsomer-cdcms"}
               }
             ] = all_enqueued()
    end

    test "doesn't blow up if county can't be found" do
      {:ok, fake_county} = ECLRS.find_or_create_county(12_345_678)

      {:ok, midsomer} = County.get(name: "midsomer")
      {:ok, midsomer_county} = ECLRS.find_or_create_county(midsomer.fips)

      {:ok, person1} = Commcare.create_person(%{data: %{}, patient_keys: ["1"], name_first: nil, name_last: nil})

      {:ok, _} =
        Commcare.create_index_case(%{
          case_id: "index-case-1",
          data: %{},
          person_id: person1.id,
          county_id: fake_county.id
        })

      {:ok, person2} = Commcare.create_person(%{data: %{}, patient_keys: ["2"], name_first: nil, name_last: nil})

      {:ok, _} =
        Commcare.create_index_case(%{
          case_id: "index-case-2",
          data: %{},
          person_id: person2.id,
          county_id: midsomer_county.id
        })

      assert :ok = RefreshIndexCases.matching(IndexCase)

      assert [
               %{
                 worker: "NYSETL.Commcare.CaseImporter",
                 priority: 3,
                 args: %{"commcare_case_id" => "index-case-2", "domain" => "uk-midsomer-cdcms"}
               }
             ] = all_enqueued()
    end
  end
end
