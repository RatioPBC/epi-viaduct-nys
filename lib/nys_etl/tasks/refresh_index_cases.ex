defmodule NYSETL.Tasks.RefreshIndexCases do
  import Ecto.Query

  alias NYSETL.Commcare.CaseImporter
  alias NYSETL.Commcare.County
  alias NYSETL.Commcare.IndexCase
  alias NYSETL.Repo

  def with_invalid_all_activity_complete_date do
    {:ok, _} =
      Repo.transaction(fn ->
        IndexCase
        |> where([ic], fragment("(data->>'all_activity_complete_date' = 'date(today())')"))
        |> Repo.stream()
        |> Stream.map(&case_importer_job/1)
        |> Stream.reject(&(&1 == :skip))
        |> Stream.chunk_every(500)
        |> Stream.each(&Oban.insert_all(&1))
        |> Stream.run()
      end)

    :ok
  end

  defp case_importer_job(%{case_id: case_id, county_id: county_id}) do
    case County.get(fips: county_id) do
      {:ok, county} ->
        %{commcare_case_id: case_id, domain: county.domain}
        |> CaseImporter.new(priority: 3, queue: :tasks)

      _ ->
        :skip
    end
  end
end
