defmodule NYSETL.Engines.E1.SQSListenerTest do
  use NYSETL.SimpleCase, async: false
  alias NYSETL.Engines.E1.SQSListener
  alias NYSETL.ExAwsMock

  @sqs_url "https://pretend_sqs_url"

  setup(context) do
    Application.put_env(:nys_etl, :sqs_queue_url, @sqs_url)
    Mox.set_mox_from_context(context)
    Mox.verify_on_exit!(context)
  end

  describe "s3 file" do
    test "success" do
      assert %{bucket: "bucket", key: "file1", receipt_handle: "rh1"} ==
               build_message("ignored", "file1", "rh1", "bucket")
               |> decode_body
               |> SQSListener.s3_file()

      assert %{bucket: "bucket", key: "COVID19_ECLRS_Export_positive_2020-10-20 0402.TXT", receipt_handle: "rh1"} ==
               build_message("ignored", "COVID19_ECLRS_Export_positive_2020-10-20+0402.TXT", "rh1", "bucket")
               |> decode_body
               |> SQSListener.s3_file()

      assert %{bucket: "bucket", key: "COVID19_ECLRS_Export_positive_2020-10-20T04:02:22-04:00.TXT", receipt_handle: "rh1"} ==
               build_message("ignored", "COVID19_ECLRS_Export_positive_2020-10-20T04%3A02%3A22-04%3A00.TXT", "rh1", "bucket")
               |> decode_body
               |> SQSListener.s3_file()
    end

    test "when message is nil it returns nil" do
      assert nil == SQSListener.s3_file(nil)
    end
  end

  describe "delete handles" do
    test "it submits a request to aws" do
      expected_delete_batch =
        ExAws.SQS.delete_message_batch(@sqs_url, [
          %{receipt_handle: "test_receipt_handle_2", id: 1},
          %{receipt_handle: "test_receipt_handle_1", id: 0}
        ])

      Mox.expect(ExAwsMock, :request!, 1, fn actual_delete_batch ->
        assert expected_delete_batch == actual_delete_batch
        :unused
      end)

      SQSListener.delete_handles([
        build_message("-", "-", "test_receipt_handle_1"),
        build_message("-", "-", "test_receipt_handle_2")
      ])
    end
  end

  describe "compact messages to most recent" do
    test "when there are no messages" do
      assert nil == SQSListener.compact_messages_to_most_recent([])
    end

    test "when there is exactly one message" do
      Mox.expect(ExAwsMock, :request, 0, fn _ -> :unused end)
      assert :first == SQSListener.compact_messages_to_most_recent([:first])
    end

    test "when there are exactly two messages" do
      expected_delete_batch =
        ExAws.SQS.delete_message_batch(@sqs_url, [
          %{receipt_handle: "rh1", id: 0}
        ])

      Mox.expect(ExAwsMock, :request!, 1, fn actual_delete_batch ->
        assert expected_delete_batch == actual_delete_batch
        :unused
      end)

      assert :first == SQSListener.compact_messages_to_most_recent([:first, %{receipt_handle: "rh1"}])
    end

    test "when there are three or more messages" do
      expected_delete_batch =
        ExAws.SQS.delete_message_batch(@sqs_url, [
          %{receipt_handle: "rh2", id: 1},
          %{receipt_handle: "rh1", id: 0}
        ])

      Mox.expect(ExAwsMock, :request!, 1, fn actual_delete_batch ->
        assert expected_delete_batch == actual_delete_batch
        :unused
      end)

      assert :first == SQSListener.compact_messages_to_most_recent([:first, %{receipt_handle: "rh1"}, %{receipt_handle: "rh2"}])
    end
  end

  describe "receive all messages" do
    test "when there is one message on the initial call to sqs" do
      Mox.expect(ExAwsMock, :request!, 1, fn _ -> %{body: %{messages: [build_message("2020-09-28T20:12:34.249Z", "file1", "rh1")]}} end)
      Mox.expect(ExAwsMock, :request!, 1, fn _ -> %{body: %{messages: []}} end)
      assert [%{receipt_handle: "rh1"}] = SQSListener.receive_all_messages("arn")
    end

    test "when we need to recurse twice" do
      messages = [
        build_message("2020-09-28T20:12:34.249Z", "file1", "rh1"),
        build_message("2020-09-28T20:11:34.249Z", "file2", "rh2"),
        build_message("2020-09-28T20:14:34.249Z", "file3", "rh3")
      ]

      Mox.expect(ExAwsMock, :request!, 1, fn _ -> %{body: %{messages: [hd(messages)]}} end)
      Mox.expect(ExAwsMock, :request!, 1, fn _ -> %{body: %{messages: tl(messages)}} end)
      Mox.expect(ExAwsMock, :request!, 1, fn _ -> %{body: %{messages: []}} end)

      assert SQSListener.receive_all_messages("arn") |> length == 3
    end

    test "when there are no messages on the initial call to sqs, it returns an empty list" do
      Mox.expect(ExAwsMock, :request!, 1, fn _ -> %{body: %{messages: []}} end)
      assert [] = SQSListener.receive_all_messages("arn")
    end
  end

  test "read new message and clear queue" do
    messages = [
      build_message("2020-09-28T20:12:34.249Z", "file1", "rh1", "bucket"),
      build_message("2020-09-28T20:20:34.249Z", "file2", "rh2", "bucket"),
      build_message("2020-09-28T20:14:34.249Z", "file3", "rh3", "bucket")
    ]

    Mox.expect(ExAwsMock, :request!, 1, fn _ -> %{body: %{messages: [hd(messages)]}} end)
    Mox.expect(ExAwsMock, :request!, 1, fn _ -> %{body: %{messages: tl(messages)}} end)
    Mox.expect(ExAwsMock, :request!, 1, fn _ -> %{body: %{messages: []}} end)
    Mox.expect(ExAwsMock, :request!, 1, fn %{action: :delete_message_batch} -> :unused end)

    assert %{bucket: "bucket", key: "file2", receipt_handle: "rh2"} = SQSListener.read_new_message_and_clear_queue()
  end

  # -- test helpers --

  defp decode_body(message), do: message |> Map.put(:body, Jason.decode!(message.body))

  defp build_message(event_time, file_name, receipt_handle, bucket \\ "bucket") do
    %{
      attributes: [],
      body:
        Jason.encode!(%{
          "Records" => [
            %{
              "awsRegion" => "us-east-1",
              "eventName" => "ObjectCreated:CompleteMultipartUpload",
              "eventSource" => "aws:s3",
              "eventTime" => event_time,
              "eventVersion" => "2.1",
              "requestParameters" => %{"sourceIPAddress" => "150.142.223.245"},
              "responseElements" => %{
                "x-amz-id-2" => "ZWYkLlXovD6h2/8+DxOWS5vYVPQVCgSPhwONIBY+rv2eeM39UwriQYBG+nhVP88qAaTr6yfPQ5fB/kxYLmCj78w2ZPdxT4Qb",
                "x-amz-request-id" => "31DEF00A637F2544"
              },
              "s3" => %{
                "bucket" => %{
                  "arn" => "arn:aws:s3:::eclrs-csv-s3bucket-110aze9xhrhec",
                  "name" => bucket,
                  "ownerIdentity" => %{"principalId" => "A2JTFNUKD9W8MU"}
                },
                "configurationId" => "sqs",
                "object" => %{
                  "eTag" => "6af3673057fccc1db5c86d46eb8fdd8b-63",
                  "key" => file_name,
                  "sequencer" => "005F7243AD4381EF45",
                  "size" => 326_735_686,
                  "versionId" => "dQbmlFuoTlETV5Bv_l85S0hRVQzHiDKd"
                },
                "s3SchemaVersion" => "1.0"
              },
              "userIdentity" => %{"principalId" => "AWS:AIDAURM6ITKTZV4QYLWKK"}
            }
          ]
        }),
      md5_of_body: "91cfaf520801879b6c3994d072257440",
      message_attributes: [],
      message_id: "6213f6aa-3f46-4de1-8c34-a01c298194ee",
      receipt_handle: receipt_handle
    }
  end
end
