defmodule NYSETL.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Cachex.Spec

  def start(_type, _args) do
    attach_telemetry_to_oban_error_reporter()

    children =
      [
        # This cache is used by Commcare.Api. Perhaps it shouldn't be global then??
        {Cachex, name: :cache, expiration: Cachex.Spec.expiration(default: :timer.minutes(30), interval: :timer.minutes(1))},
        NYSETL.Repo,
        NYSETLWeb.Telemetry,
        {Phoenix.PubSub, name: NYSETL.PubSub},
        NYSETLWeb.Endpoint,
        NYSETL.Engines.E1.Cache,
        {Mutex, name: NYSETL.Commcare.PersonMutex}
      ] ++
        viaduct_supervisor() ++
        cloudwatch_monitoring_worker()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NYSETL.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    NYSETLWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp cloudwatch_monitoring_worker() do
    if Application.get_env(:nys_etl, :cloudwatch_metrics_enabled) do
      [NYSETL.Monitoring.Supervisor]
    else
      []
    end
  end

  defp viaduct_supervisor() do
    if Application.get_env(:nys_etl, :start_viaduct_workers),
      do: [NYSETL.ViaductSupervisor],
      else: []
  end

  defp attach_telemetry_to_oban_error_reporter() do
    :ok =
      :telemetry.attach_many(
        "oban-errors",
        [[:oban, :job, :exception], [:oban, :circuit, :trip]],
        &NYSETL.Monitoring.Oban.ErrorReporter.handle_event/4,
        %{}
      )
  end
end
