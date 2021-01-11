defmodule NYSETL.Engines.E2.BroadwayTest do
  use NYSETL.DataCase, async: true

  alias NYSETL.ECLRS
  alias NYSETL.Engines.E2

  describe "ack" do
    test "creates a processed event for each successful message" do
      {:ok, county} = ECLRS.find_or_create_county(71)
      {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()
      {:ok, test_result} = Factory.test_result_attrs(county_id: county.id, file_id: file.id, tid: "no-events") |> ECLRS.create_test_result()
      message = %Broadway.Message{data: test_result, acknowledger: {E2.Broadway, :ack_id, :ack_data}}

      assert_that(Broadway.Message.ack_immediately(message),
        changes: NYSETL.Event |> Repo.count(),
        from: 0,
        to: 1
      )

      test_result
      |> Repo.preload(:events)
      |> Map.get(:events)
      |> Extra.Enum.pluck(:type)
      |> assert_eq(["processed"])
    end

    test "creates a processing_failed event for each failed message" do
      {:ok, county} = ECLRS.find_or_create_county(71)
      {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()
      {:ok, test_result} = Factory.test_result_attrs(county_id: county.id, file_id: file.id, tid: "no-events") |> ECLRS.create_test_result()

      message =
        %Broadway.Message{data: test_result, acknowledger: {E2.Broadway, :ack_id, :ack_data}}
        |> Broadway.Message.failed(:some_reason)

      assert_that(Broadway.Message.ack_immediately(message),
        changes: NYSETL.Event |> Repo.count(),
        from: 0,
        to: 1
      )

      test_result
      |> Repo.preload(:events)
      |> Map.get(:events)
      |> Extra.Enum.pluck(:type)
      |> assert_eq(["processing_failed"])
    end
  end
end
