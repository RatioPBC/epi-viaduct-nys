defmodule NYSETL.Backfillers.FilesECLRSVersion do
  use Oban.Pro.Workers.Batch, queue: :backfillers

  import Ecto.Query

  alias NYSETL.ECLRS
  alias NYSETL.Repo

  def backfill_all(batch_size \\ 1_000) do
    backfill_in_batches(batch_size: batch_size, last_processed_id: 0)
  end

  @impl true
  def process(%Oban.Job{args: %{"file_id" => file_id}}) do
    with {:ok, test_result} <- get_test_result(file_id),
         version when not is_nil(version) <- test_result_version(test_result),
         {:ok, _file} <- ECLRS.update_file(test_result.file, %{eclrs_version: version})
    do
      :ok
    else
      :test_result_not_found -> :discard
    end
  end

  defp get_test_result(file_id) do
    ECLRS.TestResult
    |> preload(:file)
    |> first()
    |> Repo.get_by(file_id: file_id)
    |> case do
      nil -> :test_result_not_found
      t -> {:ok, t}
    end
  end

  defp test_result_version(test_result) do
    [raw_data_fields] = ECLRSParser.parse_string(test_result.raw_data, skip_headers: false)
    length_of_fields = length(raw_data_fields)
    [:v1, :v2]
    |> Enum.find(fn v -> length_of_fields == length(ECLRS.File.header_names(v)) end)
    |> ECLRS.File.version_number()
  end

  defp backfill_in_batches(batch_size: batch_size, last_processed_id: last_processed_id) do
    ECLRS.File
    |> where([f], is_nil(f.eclrs_version))
    |> where([f], f.id > ^last_processed_id)
    |> order_by(asc: :id)
    |> limit(^batch_size)
    |> select([f], f.id)
    |> Repo.all()
    |> case do
      [] -> :ok
      file_ids ->
        file_ids
        |> Enum.map(fn id -> %{"file_id" => id} end)
        |> __MODULE__.new_batch()
        |> Oban.insert_all()

        backfill_in_batches(batch_size: batch_size, last_processed_id: List.last(file_ids))
    end
  end
end
