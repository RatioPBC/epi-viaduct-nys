defmodule NYSETL.Monitoring.Oban.ErrorReporter do
  require Logger

  @sentry_extras ~w{
      args
      attempt
      attempted_at
      attempted_by
      id
      inserted_at
      queue
      scheduled_at
      state
      tags
      worker
  }a

  def handle_event([:oban, :job, :exception], measure, meta, _) do
    Logger.info(mod: __MODULE__, msg: "In handle_event/4 for job exception", meta: meta, measure: measure)

    if attempt_threshold_reached?(meta[:attempt]) do
      extra = meta |> Map.take(@sentry_extras) |> Map.merge(measure)
      {message, extra} = group_noisy_messages(meta.error.message, extra)
      error = meta.error |> Map.put(:message, message)
      Sentry.capture_exception(error, stacktrace: meta.stacktrace, extra: extra)
    end
  end

  def handle_event([:oban, :circuit, :trip], measure, meta, _) do
    Logger.info(mod: __MODULE__, msg: "In handle_event/4 for circuit trip", meta: meta, measure: measure)
    Sentry.capture_exception(meta.error, stacktrace: meta.stacktrace, extra: meta)
  end

  def post_to_sentry(message, job, extras \\ %{}) do
    if attempt_threshold_reached?(job.attempt) do
      {message, extras} = group_noisy_messages(message, extras)
      {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
      extras = extras |> Map.put(:stackrace, stacktrace)
      Sentry.capture_message(message, extra: oban_job_to_sentry_extra(job, extras))
    end
  end

  @noisy_messages [
    "Sorry, this request could not be processed. Please try again later.",
    "500 Error",
    "500 Internal Server Error",
    "502 Bad Gateway",
    "CommCareHQ is currently undergoing maintenance"
  ]

  def group_noisy_messages(message, extras) do
    if Enum.find(@noisy_messages, fn noisy -> String.contains?(message, noisy) end),
      do: {"suspected commcare server error/issue", Map.merge(extras, %{message: message})},
      else: {message, extras}
  end

  defp oban_job_to_sentry_extra(job, extras) do
    Map.take(job, @sentry_extras)
    |> Map.merge(extras)
  end

  defp attempt_threshold_reached?(attempt) do
    Application.fetch_env!(:nys_etl, :oban_error_reporter_attempt_threshold) <= attempt
  end
end
