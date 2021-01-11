defmodule NYSETL.Monitoring.Transformer.FailureReporter do
  # Change to :cron?
  use Oban.Worker, queue: :commcare

  import Ecto.Query

  @impl Oban.Worker
  @spec perform(any) :: {:ok, integer}
  def perform(_job) do
    count = count_processing_failed()
    :telemetry.execute([:db, :events, :processing_failed], %{count: count})
    {:ok, count}
  end

  @one_week 7 * 24 * 60 * 60

  @spec count_processing_failed :: integer()
  def count_processing_failed() do
    one_week_ago = DateTime.utc_now() |> DateTime.add(-1 * @one_week)

    from(e in NYSETL.Event,
      where: e.type == "processing_failed",
      where: e.inserted_at > ^one_week_ago,
      select: count(e.id)
    )
    |> NYSETL.Repo.one()
  end
end
