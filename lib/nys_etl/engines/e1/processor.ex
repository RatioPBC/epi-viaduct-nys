defmodule NYSETL.Engines.E1.Processor do
  @moduledoc """
  Given the raw data of a row from an ECLRS file, create a
  TestResult record.

  ## Outcomes

  * Checksum of the row has already been seen. Update the `last_seen_file_id` for the existing
    record
  * Checksum has not been seen. Create a new TestResult with an About.
  """

  alias NYSETL.ECLRS
  alias NYSETL.Engines.E1
  alias NYSETL.Repo

  def process(%E1.Message{} = message) do
    current_file_id = message.file_id

    E1.Cache.transaction(message.checksum, fn cache ->
      get_about(message.checksum, cache)
      |> case do
        {:ok, %{last_seen_file_id: ^current_file_id} = about} ->
          {:ok, :duplicate, about}

        {:ok, about} ->
          cached_about =
            about
            |> Map.take(ECLRS.About.__schema__(:fields))
            |> Map.merge(%{last_seen_file_id: current_file_id})

          E1.Cache.put!(cache, message.checksum, cached_about)

          {:ok, :update, about}

        {:error, :not_found} ->
          {:error, :not_found}
      end
    end)
    |> case do
      {:ok, _, _} = ok -> ok
      {:error, :not_found} -> find_or_create(message)
    end
  end

  def get_about(checksum, cache) do
    E1.Cache.get(cache, checksum)
    |> case do
      {:ok, nil} -> ECLRS.get_about(checksum: checksum)
      {:ok, cache} -> {:ok, %ECLRS.About{} |> Map.merge(cache)}
    end
  end

  def find_or_create(message) do
    message_attrs = E1.Message.parse(message)
    ECLRS.find_or_create_county(message_attrs.county_id)

    Repo.transaction(fn ->
      {:ok, test_result} =
        message_attrs
        |> ECLRS.create_test_result()

      test_result
      |> ECLRS.About.from_test_result(message.checksums, message.file)
      |> ECLRS.create_about()
      |> case do
        {:ok, about} ->
          E1.Cache.put!(message.checksum, about |> Map.take(ECLRS.About.__schema__(:fields)))
          {:ok, :new, about}

        {:error, changeset} ->
          {:error, changeset.data}
      end
    end)
    |> case do
      {:ok, response} -> response
      {:error, :rollback} -> {:error, message_attrs}
    end
  end
end
