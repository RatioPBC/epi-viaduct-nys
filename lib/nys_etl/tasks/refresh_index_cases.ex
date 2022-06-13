defmodule NYSETL.Tasks.RefreshIndexCases do
  import Ecto.Query

  alias NYSETL.Commcare.CaseImporter
  alias NYSETL.Commcare.County
  alias NYSETL.Commcare.IndexCase
  alias NYSETL.Repo

  @default_limit 1_000

  def matching(queryable, limit \\ @default_limit) do
    {:ok, _} =
      Repo.transaction(
        fn ->
          queryable
          |> limit(^limit)
          |> Repo.stream()
          |> Stream.map(&case_importer_job/1)
          |> Stream.reject(&(&1 == :skip))
          |> Stream.chunk_every(500)
          |> Stream.each(&Oban.insert_all(&1))
          |> Stream.run()
        end,
        timeout: :infinity
      )

    :ok
  end

  defp case_importer_job(%IndexCase{case_id: case_id, county_id: county_id}) do
    case County.get(fips: county_id) do
      {:ok, county} ->
        %{commcare_case_id: case_id, domain: county.domain}
        |> CaseImporter.new(priority: 3)

      _ ->
        :skip
    end
  end
end
