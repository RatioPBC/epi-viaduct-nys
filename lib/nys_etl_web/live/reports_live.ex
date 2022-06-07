defmodule NYSETLWeb.ReportsLive do
  use NYSETLWeb, :live_view

  alias NYSETL.Commcare
  alias NYSETL.ECLRS
  alias NYSETL.Repo

  @timeout 60_000 * 5

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        test_results_count: nil,
        index_cases_count: nil,
        processing_index_cases: false
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("count_test_results", _, socket) do
    {:ok, count} =
      Repo.transaction(
        fn ->
          ECLRS.get_unprocessed_test_results() |> Repo.count()
        end,
        timeout: @timeout
      )

    {:noreply, assign(socket, test_results_count: count)}
  end

  @impl true
  def handle_event("count_index_cases", _, socket) do
    {:ok, count} =
      Repo.transaction(
        fn ->
          Commcare.get_unprocessed_index_cases() |> Repo.count()
        end,
        timeout: @timeout
      )

    {:noreply, assign(socket, index_cases_count: count)}
  end
end
