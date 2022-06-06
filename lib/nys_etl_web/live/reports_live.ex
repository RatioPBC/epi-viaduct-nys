defmodule NYSETLWeb.ReportsLive do
  use NYSETLWeb, :live_view

  alias NYSETL.ECLRS
  alias NYSETL.Repo

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, test_results_count: nil)}
  end

  @impl true
  def handle_event("count_test_results", _, socket) do
    count = ECLRS.get_unprocessed_test_results() |> Repo.count()
    {:noreply, assign(socket, test_results_count: count)}
  end
end
