defmodule NYSETL.Engines.E1.SQSTask do
  use Task, restart: :permanent
  require Logger

  alias NYSETL.Engines.E1

  def start_link(_) do
    Logger.info("[#{__MODULE__}] Starting SQSTask")
    Task.start_link(__MODULE__, :loop, [])
  end

  def pick_file_location(key) do
    [directory: true]
    |> Briefly.create!()
    |> Path.join(key)
  end

  def loop() do
    E1.SQSListener.transaction(&import_s3_file/1)
    loop()
  end

  def processable?(key), do: key |> String.downcase() |> String.ends_with?(".txt")

  def import_s3_file(key: key, bucket: bucket) do
    Logger.info("[#{__MODULE__}] received new key `#{key}`")

    if processable?(key) do
      path = pick_file_location(key)

      try do
        bucket
        |> ExAws.S3.download_file(key, path)
        |> ExAws.request!()

        Logger.info("[#{__MODULE__}] downloaded new eclrs file #{key} to #{path}")

        E1.ECLRSFileExtractor.extract!(path)
      after
        ensure_deleted(path)
      end
    else
      Logger.error("[#{__MODULE__}] unable to process key `#{key}`")
    end
  end

  def ensure_deleted(path) do
    case File.rm(path) do
      :ok ->
        Logger.info("[#{__MODULE__}] deleted temp file #{path}")

      {:error, reason} ->
        Logger.error("[#{__MODULE__}] failed to delete temp file #{path}: #{reason}")
        {:error, reason}
    end
  end
end
