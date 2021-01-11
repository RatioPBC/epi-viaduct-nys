defmodule NYSETL.Monitoring.SupervisorTest do
  use NYSETL.SimpleCase, async: false
  import ExUnit.CaptureLog

  alias NYSETL.Monitoring.Supervisor

  test "validation of metric configurations" do
    metrics = Supervisor.metrics()

    assert capture_log(fn ->
             # validate_metrics is limited in what it examines
             TelemetryMetricsCloudwatch.Cache.validate_metrics(metrics)
           end) == ""
  end
end
