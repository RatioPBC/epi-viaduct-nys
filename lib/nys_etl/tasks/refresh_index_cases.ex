defmodule NYSETL.Tasks.RefreshIndexCases do
  import Ecto.Query

  alias NYSETL.Commcare.CaseImporter
  alias NYSETL.Commcare.County
  alias NYSETL.Commcare.IndexCase
  alias NYSETL.Repo

  @default_limit 1_000

  def with_invalid_all_activity_complete_date(limit \\ @default_limit) do
    dynamic([_ic], fragment("(data->>'all_activity_complete_date' = 'date(today())')"))
    |> refresh_all(limit)
  end

  def without_commcare_date_modified(limit \\ @default_limit) do
    dynamic([ic], is_nil(ic.commcare_date_modified))
    |> refresh_all(limit)
  end

  defp refresh_all(filter, limit) do
    {:ok, _} =
      Repo.transaction(
        fn ->
          IndexCase
          |> where([ic], ^filter)
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

  defp case_importer_job(%{case_id: case_id, county_id: county_id}) do
    case County.get(fips: county_id) do
      {:ok, county} ->
        %{commcare_case_id: case_id, domain: county.domain}
        |> CaseImporter.new(priority: 3)

      _ ->
        :skip
    end
  end
end
