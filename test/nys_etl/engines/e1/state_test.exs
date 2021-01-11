defmodule NYSETL.Engines.E1.StateTest do
  use NYSETL.DataCase, async: false

  alias NYSETL.ECLRS
  alias NYSETL.Engines.E1.State

  ExUnit.Case.register_attribute(__MODULE__, :initial_state)

  setup context do
    {:ok, eclrs_file} = Factory.file_attrs() |> ECLRS.create_file()

    initial =
      %State{status: :finished, processed_count: 26, file: eclrs_file}
      |> Map.merge(context.registered.initial_state)

    pid = start_supervised!({State, eclrs_file})
    :sys.replace_state(pid, fn _ -> initial end)
    [eclrs_file: eclrs_file]
  end

  describe "finish_reads" do
    @initial_state %{status: :loading, processed_count: 12, line_count: 12}
    test "sets status to :read_complete and saves line_count" do
      22
      |> State.finish_reads()
      |> assert_eq(:ok)

      State.get()
      |> assert_eq(
        %{
          line_count: 22,
          status: :read_complete
        },
        only: ~w{line_count status}a
      )
    end

    @initial_state %{status: :finished, processed_count: 26, line_count: 40}
    test "when status is already finished, does nothing" do
      22
      |> State.finish_reads()
      |> assert_eq(:ok)

      State.get()
      |> assert_eq(
        %{
          line_count: 40,
          status: :finished
        },
        only: ~w{line_count status}a
      )
    end

    @initial_state %{status: :loading, processed_count: 26, line_count: 0}
    test "when status has already processed all lines, transitions to :finished" do
      26
      |> State.finish_reads()
      |> assert_eq(:ok)

      State.get()
      |> assert_eq(
        %{
          line_count: 26,
          processed_count: 26,
          status: :finished
        },
        only: ~w{line_count processed_count status}a
      )
    end
  end
end
