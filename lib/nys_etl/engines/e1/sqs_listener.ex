defmodule NYSETL.Engines.E1.SQSListener do
  use Magritte

  def get_queue_url_from_config,
    do: Application.get_env(:nys_etl, :sqs_queue_url)

  def exaws,
    do: Application.get_env(:nys_etl, :ex_aws, ExAws)

  def read_new_message_and_clear_queue do
    get_queue_url_from_config()
    |> receive_all_messages()
    |> compact_messages_to_most_recent()
    |> s3_file()
  end

  def receive_all_messages(queue_url, messages \\ []) do
    %{body: %{messages: new_messages}} =
      queue_url
      |> ExAws.SQS.receive_message(max_number_of_messages: 10)
      |> exaws().request!()

    new_messages =
      new_messages
      |> Enum.map(fn message ->
        message |> Map.put(:body, Jason.decode!(message.body))
      end)

    case new_messages do
      [] -> messages |> Enum.sort_by(fn element -> element |> get_in([:body, "Records"]) |> hd |> Map.get("eventTime") end, :desc)
      _ -> receive_all_messages(queue_url, messages ++ new_messages)
    end
  end

  def compact_messages_to_most_recent([newest_message]) do
    newest_message
  end

  def compact_messages_to_most_recent([newest_message | older_messages]) do
    delete_handles(older_messages)
    newest_message
  end

  def compact_messages_to_most_recent([]) do
    nil
  end

  def delete_handles(messages) when is_list(messages) do
    batch =
      Enum.reduce(messages, [], fn message, list ->
        [%{id: length(list), receipt_handle: message.receipt_handle} | list]
      end)

    get_queue_url_from_config()
    |> ExAws.SQS.delete_message_batch(batch)
    |> exaws().request!()
  end

  def s3_file(nil), do: nil

  def s3_file(%{body: body, receipt_handle: receipt_handle}) do
    record = body |> Map.get("Records") |> hd |> Map.get("s3")
    bucket = get_in(record, ["bucket", "name"])
    # The key is URL encoded as a query param and needs to be decoded as part of a query
    key = record |> get_in(["object", "key"]) |> Kernel.<>("key=", ...) |> URI.decode_query() |> Map.get("key")
    %{bucket: bucket, key: key, receipt_handle: receipt_handle}
  end

  def transaction(fun) do
    case read_new_message_and_clear_queue() do
      %{key: key, bucket: bucket, receipt_handle: receipt_handle} ->
        fun.(key: key, bucket: bucket)

        get_queue_url_from_config()
        |> ExAws.SQS.delete_message(receipt_handle)
        |> exaws().request!()

        :ok

      _ ->
        :ok
    end
  end
end
