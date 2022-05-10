defmodule NYSETL.Tasks.RefreshIndexCasesTest do
  use NYSETL.DataCase, async: false
  use Oban.Testing, repo: NYSETL.Repo

  alias NYSETL.Commcare
  alias NYSETL.Commcare.CaseImporter
  alias NYSETL.Commcare.County
  alias NYSETL.ECLRS
  alias NYSETL.Tasks.RefreshIndexCases

  setup :start_supervised_oban

  describe "with_invalid_all_activity_complete_date" do
    test "enqueues jobs only for cases with all_activity_complete_date=date(today())" do
      {:ok, midsomer} = County.get(name: "midsomer")
      {:ok, midsomer_county} = ECLRS.find_or_create_county(midsomer.fips)

      {:ok, camden} = County.get(name: "midsomer")
      {:ok, camden_county} = ECLRS.find_or_create_county(camden.fips)

      {:ok, person1} = Commcare.create_person(%{data: %{}, patient_keys: ["1"], name_first: nil, name_last: nil})

      {:ok, _} =
        Commcare.create_index_case(%{
          case_id: "index-case-1",
          data: %{"all_activity_complete_date" => "date(today())"},
          person_id: person1.id,
          county_id: midsomer_county.id
        })

      {:ok, person2} = Commcare.create_person(%{data: %{}, patient_keys: ["2"], name_first: nil, name_last: nil})

      {:ok, _} =
        Commcare.create_index_case(%{
          case_id: "index-case-2",
          data: %{"all_activity_complete_date" => "2022-05-04"},
          person_id: person2.id,
          county_id: midsomer_county.id
        })

      {:ok, person3} = Commcare.create_person(%{data: %{}, patient_keys: ["3"], name_first: nil, name_last: nil})

      {:ok, _} =
        Commcare.create_index_case(%{
          case_id: "index-case-3",
          data: %{"all_activity_complete_date" => ""},
          person_id: person3.id,
          county_id: camden_county.id
        })

      assert :ok = RefreshIndexCases.with_invalid_all_activity_complete_date()

      assert_enqueued(
        worker: CaseImporter,
        priority: 3,
        queue: :tasks,
        args: %{commcare_case_id: "index-case-1", domain: "uk-midsomer-cdcms"}
      )

      refute_enqueued(worker: CaseImporter, args: %{commcare_case_id: "index-case-2", domain: "uk-midsomer-cdcms"})
      refute_enqueued(worker: CaseImporter, args: %{commcare_case_id: "index-case-3", domain: "uk-camden-cdcms"})
    end

    test "doesn't blow up if county can't be found" do
      {:ok, fake_county} = ECLRS.find_or_create_county(12_345_678)

      {:ok, midsomer} = County.get(name: "midsomer")
      {:ok, midsomer_county} = ECLRS.find_or_create_county(midsomer.fips)

      {:ok, person1} = Commcare.create_person(%{data: %{}, patient_keys: ["1"], name_first: nil, name_last: nil})

      {:ok, _} =
        Commcare.create_index_case(%{
          case_id: "index-case-1",
          data: %{"all_activity_complete_date" => "date(today())"},
          person_id: person1.id,
          county_id: fake_county.id
        })

      {:ok, person2} = Commcare.create_person(%{data: %{}, patient_keys: ["2"], name_first: nil, name_last: nil})

      {:ok, _} =
        Commcare.create_index_case(%{
          case_id: "index-case-2",
          data: %{"all_activity_complete_date" => "date(today())"},
          person_id: person2.id,
          county_id: midsomer_county.id
        })

      assert :ok = RefreshIndexCases.with_invalid_all_activity_complete_date()

      assert_enqueued(
        worker: CaseImporter,
        priority: 3,
        queue: :tasks,
        args: %{commcare_case_id: "index-case-2", domain: "uk-midsomer-cdcms"}
      )
    end
  end
end
