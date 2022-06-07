defmodule NYSETL.Tasks.EnqueueIndexCases do
  import Ecto.Query

  alias NYSETL.Commcare
  alias NYSETL.Commcare.County
  alias NYSETL.Engines.E4.CommcareCaseLoader
  alias NYSETL.Repo

  @default_limit 1_000

  def not_sent_to_commcare(limit \\ @default_limit) do
    {:ok, _} =
      Repo.transaction(
        fn ->
          Commcare.get_unprocessed_index_cases()
          |> limit(^limit)
          |> Repo.stream()
          |> Stream.each(&enqueue_commcare_case_loader/1)
          |> Stream.run()
        end,
        timeout: :infinity
      )

    :ok
  end

  defp enqueue_commcare_case_loader(index_case) do
    {:ok, county} = County.get(fips: index_case.county_id)
    CommcareCaseLoader.enqueue(index_case, county)
  end
end
