defmodule NYSETL.Monitoring.Supervisor do
  use Supervisor
  alias Telemetry.Metrics

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @push_interval_ms 10_000

  @impl true
  def init(_) do
    namespace = ["Viaduct", Application.get_env(:nys_etl, :environment_name)] |> Enum.join(".")

    Supervisor.init(
      [{TelemetryMetricsCloudwatch, metrics: metrics(), namespace: namespace, push_interval: @push_interval_ms}],
      strategy: :one_for_all
    )
  end

  def metrics() do
    eclrs_metrics() ++
      loader_metrics() ++
      transform_metrics() ++
      commcare_metrics() ++
      extractor_metrics() ++
      db_metrics()
  end

  defp eclrs_metrics(),
    do: [
      Metrics.sum("extractor.eclrs.broadway.duplicate.count"),
      Metrics.sum("extractor.eclrs.broadway.error.count"),
      Metrics.sum("extractor.eclrs.broadway.matched.count"),
      Metrics.sum("extractor.eclrs.broadway.new.count"),
      Metrics.sum("extractor.eclrs.file_reader.open.count"),
      Metrics.sum("extractor.eclrs.file_reader.read.count"),
      Metrics.summary("broadway.pipeline.process.time", unit: :millisecond)
    ]

  defp loader_metrics(),
    do: [
      Metrics.sum("loader.commcare.api_error.count"),
      Metrics.sum("loader.commcare.create.count"),
      Metrics.sum("loader.commcare.enqueued.count"),
      Metrics.sum("loader.commcare.error.count"),
      Metrics.sum("loader.commcare.rate_limited.count"),
      Metrics.sum("loader.commcare.transfer.already_exists_locally.count"),
      Metrics.sum("loader.commcare.transfer.created_locally.count"),
      Metrics.sum("loader.commcare.transfer.cycle_detected.count"),
      Metrics.sum("loader.commcare.transfer.found.count"),
      Metrics.sum("loader.commcare.transfer.not_found.count"),
      Metrics.sum("loader.commcare.update.count"),
      Metrics.sum("loader.commcare.updated_from_commcare.count"),
      Metrics.summary("loader.index_case_producer.initial_query.time", unit: :millisecond),
      Metrics.summary("loader.index_case_producer.subsequent_query.time", unit: :millisecond)
    ]

  defp extractor_metrics(),
    do: [
      Metrics.sum("extractor.commcare.index_case.already_exists.count"),
      Metrics.sum("extractor.commcare.index_case.created.count"),
      Metrics.sum("extractor.commcare.lab_result.created.count"),
      Metrics.sum("extractor.commcare.index_case.with_lab_result.person_not_found.count"),
      Metrics.sum("extractor.commcare.index_case.without_lab_result.person_not_found.count"),
      Metrics.sum("extractor.commcare.index_case.stub_found.count"),
      Metrics.sum("extractor.commcare.produced.count")
    ]

  defp transform_metrics(),
    do: [
      Metrics.sum("transformer.person.added_patient_key.count"),
      Metrics.sum("transformer.person.created.count"),
      Metrics.sum("transformer.person.found.count"),
      Metrics.sum("transformer.lab_result.processed.count"),
      Metrics.sum("transformer.lab_result.processing_failed.count"),
      Metrics.summary("transformer.test_result_producer.initial_query.time", unit: :millisecond),
      Metrics.summary("transformer.test_result_producer.subsequent_query.time", unit: :millisecond)
    ]

  defp commcare_metrics(),
    do: [
      Metrics.sum("api.commcare.get_case.error.count"),
      Metrics.sum("api.commcare.get_case.not_found.count"),
      Metrics.sum("api.commcare.get_case.rate_limited.count"),
      Metrics.sum("api.commcare.get_case.success.count"),
      Metrics.sum("api.commcare.get_cases.error.count"),
      Metrics.sum("api.commcare.get_cases.success.count"),
      Metrics.sum("api.commcare.get_county_list.error.count"),
      Metrics.sum("api.commcare.get_county_list.success.count"),
      Metrics.sum("api.commcare.post_case.error.count"),
      Metrics.sum("api.commcare.post_case.rate_limited.count"),
      Metrics.sum("api.commcare.post_case.success.count")
    ]

  defp db_metrics(),
    do: [
      Metrics.last_value("db.events.processing_failed.count")
    ]
end
