defmodule NYSETL.Backfillers.AboutsChecksums do
  use Oban.Worker, queue: :backfillers

  import Ecto.Query

  alias NYSETL.ECLRS
  alias NYSETL.Repo

  def backfill_all(batch_size \\ 1_000, last_processed_id \\ 0) do
    __MODULE__.new(%{"action" => "backfill", "batch_size" => batch_size, "last_processed_id" => last_processed_id})
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%{args: %{"action" => "backfill", "batch_size" => batch_size, "last_processed_id" => last_processed_id}}) do
    ECLRS.About
    |> where([a], is_nil(a.checksums))
    |> where([a], a.id > ^last_processed_id)
    |> order_by(asc: :id)
    |> limit(^batch_size)
    |> select([a], a.id)
    |> Repo.all()
    |> case do
      [] ->
        :ok

      about_ids ->
        {:ok, _} =
          Repo.transaction(fn ->
            about_ids
            |> Enum.map(fn id -> __MODULE__.new(%{"action" => "calculate_about_checksums", "about_id" => id}) end)
            |> Oban.insert_all()

            backfill_all(batch_size, List.last(about_ids))
          end)

        :ok
    end
  end

  @impl Oban.Worker
  def perform(%{args: %{"action" => "calculate_about_checksums", "about_id" => about_id}}) do
    with {:ok, about} <- get_about(about_id),
         checksums = checksums(about.test_result),
         {:ok, checksums} <- validate_checksums_match(about.checksum, checksums) do
      ECLRS.update_about(about, %{checksums: checksums})
    else
      {:error_checksums_dont_match, reason} -> {:error, reason}
    end
  end

  defp get_about(about_id) do
    {:ok, about} = ECLRS.get_about(id: about_id)
    {:ok, Repo.preload(about, test_result: :file)}
  end

  defp checksums(test_result) do
    ECLRS.Checksum.checksums(test_result.raw_data, test_result.file)
  end

  defp validate_checksums_match(about_checksum, checksums) do
    new_checksum = checksums.v1

    if about_checksum == new_checksum do
      {:ok, checksums}
    else
      ECLRS.get_about(checksum: new_checksum)
      |> case do
        {:ok, about} -> {:ok, duplicate_checksums(about.checksums, checksums)}

        _ ->
          {:error_checksums_dont_match, "Checksums don't match. Current: #{about_checksum} - New: #{new_checksum}"}
      end
    end
  end

  defp duplicate_checksums(existing_checksums, new_checksums) do
    new_checksums |> Map.new(fn {key, value} ->
      if Map.get(existing_checksums, key) == value do
        {key, "duplicate-#{value}"}
      else
        {key, value}
      end
    end)
  end
end
