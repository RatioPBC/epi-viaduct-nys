defmodule NYSETL.Engines.E1.Broadway do
  @moduledoc """
  Reads an ECLRS file and processes it with high concurrency.
  """

  use Broadway

  alias Broadway.Message
  alias Euclid.Extra
  alias NYSETL.ECLRS
  alias NYSETL.Engines.E1
  require Logger

  def start_link(file) do
    Broadway.start_link(__MODULE__,
      name: E1,
      context: %{file: file},
      producer: [
        module: {E1.FileReader, file},
        concurrency: 1,
        transformer: {__MODULE__, :transform, [file: file]}
      ],
      processors: [
        default: [concurrency: concurrency()]
      ],
      batchers: [
        duplicate: [concurrency: concurrency(), batch_size: 5],
        error: [concurrency: concurrency(), batch_size: 5],
        new: [concurrency: concurrency(), batch_size: 10],
        update: [concurrency: concurrency(), batch_size: 10]
      ],
      partition_by: &partition/1
    )
  end

  def transform(data, file: file) do
    %Message{
      data: E1.Message.transform(data, file),
      acknowledger: {__MODULE__, :ack_id, :ack_data}
    }
  end

  def handle_message(_, %Message{} = message, _) do
    message.data
    |> E1.Processor.process()
    |> case do
      {:ok, :duplicate, about} -> message |> Message.put_batcher(:duplicate) |> update_message(about)
      {:ok, :new, about} -> message |> Message.put_batcher(:new) |> update_message(about)
      {:ok, :update, about} -> message |> Message.put_batcher(:update) |> update_message(about)
      {:error, data} -> message |> Message.put_batcher(:error) |> update_message(data)
    end
  end

  def handle_failed(messages, context) do
    warn("failed messages: #{inspect(messages)}, context: #{inspect(context)}")
    E1.State.update_processed_count(length(messages))
    messages
  end

  def handle_batch(:duplicate, messages, _batch_info, _context) do
    messages
    |> by_county()
    |> E1.State.update_duplicate_count()

    count = length(messages)
    :telemetry.execute([:extractor, :eclrs, :broadway, :duplicate], %{count: count})
    E1.State.update_processed_count(count)

    messages
  end

  def handle_batch(:error, messages, _batch_info, _context) do
    messages
    |> by_county()
    |> E1.State.update_error_count()

    count = length(messages)
    :telemetry.execute([:extractor, :eclrs, :broadway, :error], %{count: count})
    E1.State.update_processed_count(count)

    messages
  end

  def handle_batch(:new, messages, _batch_info, _context) do
    messages
    |> by_county()
    |> E1.State.update_new_count()

    count = length(messages)
    :telemetry.execute([:extractor, :eclrs, :broadway, :new], %{count: count})
    E1.State.update_processed_count(count)

    messages
  end

  def handle_batch(:update, messages, _batch_info, %{file: file}) do
    messages
    |> Extra.Enum.pluck(:data)
    |> ECLRS.update_last_seen_file(file)

    messages
    |> by_county()
    |> E1.State.update_matched_count()

    count = length(messages)
    :telemetry.execute([:extractor, :eclrs, :broadway, :matched], %{count: count})
    E1.State.update_processed_count(count)

    messages
  end

  def ack(:ack_id, _successful, _failed) do
    :ok
  end

  def warn(msg), do: Logger.warn("[Broadway] #{String.trim(msg)}")
  defp by_county(messages), do: messages |> Enum.reduce(%{}, fn message, acc -> acc |> Map.update(message.data.county_id, 1, &(&1 + 1)) end)
  defp concurrency(), do: Kernel.trunc(System.schedulers_online() * 1.5)
  defp update_message(message, term), do: message |> Message.update_data(fn _data -> term end)
  defp partition(msg), do: :erlang.phash2(msg.data.checksum)
end
