defmodule NYSETL.Tasks.EnqueueIndexCasesTest do
  use NYSETL.DataCase, async: false
  use Oban.Testing, repo: NYSETL.Repo

  alias NYSETL.Commcare
  alias NYSETL.ECLRS
  alias NYSETL.Engines.E4.CommcareCaseLoader
  alias NYSETL.Tasks.EnqueueIndexCases

  setup :start_supervised_oban

  test "not_sent_to_commcare" do
    {:ok, _county} = ECLRS.find_or_create_county(1111)
    {:ok, _county} = ECLRS.find_or_create_county(9999)
    {:ok, _county} = ECLRS.find_or_create_county(1234)

    person = %{data: %{}, patient_keys: ["123"]} |> Commcare.Person.changeset() |> Repo.insert!()

    {:ok, %{case_id: processed_id} = processed_index_case} = %{data: %{}, person_id: person.id, county_id: 1111} |> Commcare.create_index_case()
    Commcare.save_event(processed_index_case, "send_to_commcare_succeeded")

    {:ok, %{case_id: enqueued_id} = enqueued_index_case} = %{data: %{}, person_id: person.id, county_id: 9999} |> Commcare.create_index_case()
    Commcare.save_event(enqueued_index_case, "send_to_commcare_succeeded")
    Commcare.save_event(enqueued_index_case, "send_to_commcare_enqueued")

    {:ok, %{case_id: unprocessed_id}} = %{data: %{}, person_id: person.id, county_id: 1234} |> Commcare.create_index_case()

    EnqueueIndexCases.not_sent_to_commcare()

    assert_enqueued(worker: CommcareCaseLoader, args: %{"case_id" => enqueued_id, "county_id" => "9999"})
    assert_enqueued(worker: CommcareCaseLoader, args: %{"case_id" => unprocessed_id, "county_id" => "1234"})
    refute_enqueued(worker: CommcareCaseLoader, args: %{"case_id" => processed_id, "county_id" => "1111"})
  end
end
