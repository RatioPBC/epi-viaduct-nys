defmodule NYSETL.Engines.E4.CommcareCaseLoader do
  @moduledoc """
  Runs in Oban to put data about an IndexCase record into CommCare.
  """

  use Oban.Worker, queue: :commcare, unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  require Logger

  alias NYSETL.Commcare
  alias NYSETL.Commcare.County
  alias NYSETL.Engines.E4.{CaseIdentifier, CaseTransferChain, Data, Diff, Transfer, XmlBuilder}
  alias NYSETL.Monitoring.Oban.ErrorReporter

  def enqueue(index_case, county) do
    Commcare.save_event(index_case, "send_to_commcare_enqueued")

    new(%{"case_id" => index_case.case_id, "county_id" => county.fips})
    |> Oban.insert!()

    :telemetry.execute([:loader, :commcare, :enqueued], %{count: 1})
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)

  # This is a test to see if we get better stacktraces---it seems perform/1 gets inlined
  # into Oban.  We got a "FunctionClauseError - no function clause matching in
  # NYSETL.Loader.CommcareCaseLoader.record_commcare_response/6" with caller being reported as
  # "lib/oban/queue/executor.ex in Oban.Queue.Executor.perform_inline/1".
  @impl Oban.Worker
  def perform(job), do: perform1(job)

  def perform1(%{args: %{"case_id" => case_id, "county_id" => county_id}} = job) do
    {:ok, %{domain: domain}} = County.get(fips: county_id)

    CaseIdentifier.new(case_id: case_id, county_domain: domain, county_id: county_id)
    |> CaseTransferChain.follow_transfers(job)
    |> CaseTransferChain.resolve()
    |> perform2(job)
  end

  def perform2({:not_found, :no_transfer}, %{args: %{"case_id" => case_id, "county_id" => county_id}} = job) do
    {:ok, %{domain: domain, location_id: location_id}} = County.get(fips: county_id)

    {:ok, index_case} = Commcare.get_index_case(case_id: case_id, county_id: county_id)
    diff_summary = Diff.case_diff_summary(index_case, nil)
    {action, updated_index_case} = maybe_update_index_case(index_case, :not_found, nil, domain)
    now = DateTime.utc_now()

    updated_index_case
    |> Data.from_index_case(location_id, now)
    |> XmlBuilder.build()
    |> post_case(domain, case_id)
    |> record_commcare_response(updated_index_case, now, action, diff_summary, job)
  end

  def perform2({{:ok, case_data}, :no_transfer}, %{args: %{"case_id" => case_id, "county_id" => county_id}} = job) do
    {:ok, %{location_id: location_id, domain: domain}} = County.get(fips: county_id)
    {:ok, index_case} = Commcare.get_index_case(case_id: case_data.case_id, county_id: county_id)
    diff_summary = Diff.case_diff_summary(index_case, case_data)
    {action, updated_index_case} = maybe_update_index_case(index_case, :found, case_data, domain)
    now = DateTime.utc_now()

    updated_index_case
    |> Data.from_index_case(location_id, now)
    |> XmlBuilder.build()
    |> post_case(domain, case_id)
    |> record_commcare_response(updated_index_case, now, action, diff_summary, job)
  end

  def perform2({:not_found, :transfer}, %{args: %{"case_id" => case_id, "county_id" => county_id}} = _job) do
    {:ok, %{domain: domain}} = County.get(fips: county_id)
    message = report_transfer_target_not_found(case_id, domain)
    {:error, message}
  end

  def perform2({{:ok, case_data}, :transfer}, %{args: %{"case_id" => case_id, "county_id" => county_id}} = job) do
    {:ok, %{domain: source_domain}} = County.get(fips: county_id)
    {:ok, index_case} = Commcare.get_index_case(case_id: case_id, county_id: county_id)

    {:ok, %{fips: destination_fips, domain: destination_domain, location_id: destination_county_location_id}} =
      County.get(domain: case_data.county_domain)
      |> case do
        {:ok, county} -> {:ok, county}
        {:non_participating, %{}} -> County.statewide_county()
      end

    {:ok, destination_index_case, created_or_updated} =
      Transfer.find_or_create_transferred_index_case_and_lab_results(index_case, case_data, destination_fips)

    report_index_case_rerouted(index_case, destination_index_case)

    :telemetry.execute([:loader, :commcare, :transfer, :found], %{count: 1})

    if created_or_updated == :created do
      :telemetry.execute([:loader, :commcare, :transfer, :created_locally], %{count: 1})

      Logger.info(
        "[#{__MODULE__}] case_id=#{index_case.case_id} in commcare domain=#{source_domain} was transferred to case_id=#{destination_index_case.case_id} in commcare domain=#{destination_domain}. Creating new index_case."
      )
    else
      :telemetry.execute([:loader, :commcare, :transfer, :already_exists_locally], %{count: 1})

      Logger.info(
        "[#{__MODULE__}] case_id=#{index_case.case_id} in commcare domain=#{source_domain} was transferred to case_id=#{destination_index_case.case_id} in commcare domain=#{destination_domain}. Updating index_case."
      )
    end

    diff_summary = Diff.case_diff_summary(destination_index_case, case_data)
    {action, updated_destination_index_case} = maybe_update_index_case(destination_index_case, :found, case_data, destination_domain)
    now = DateTime.utc_now()

    updated_destination_index_case
    |> Data.from_index_case(destination_county_location_id, now)
    |> XmlBuilder.build()
    |> post_case(destination_domain, destination_index_case.case_id)
    |> record_commcare_response(updated_destination_index_case, now, action, diff_summary, job)
  end

  def perform2({:cycle_detected, _transfer?}, %{args: %{"case_id" => case_id, "county_id" => county_id}} = _job) do
    {:ok, index_case} = Commcare.get_index_case(case_id: case_id, county_id: county_id)
    report_cycle_detected(index_case)
    :discard
  end

  def perform2({{:error, :rate_limited}, _transfer?}, %{args: %{"case_id" => case_id, "county_id" => county_id}} = _job) do
    report_rate_limited(case_id, county_id)
    {:snooze, 1}
  end

  def perform2({{:error, error}, _transfer?}, _job) do
    report_non_specific_error()
    {:error, error}
  end

  defp maybe_update_index_case(index_case, :found, patient_case_data, domain) do
    Commcare.update_index_case_from_commcare_data(index_case, patient_case_data.data)
    |> case do
      {:ok, ^index_case} ->
        Logger.info("[#{__MODULE__}] not modified case_id=#{index_case.case_id} in commcare domain=#{domain}")
        {:update, index_case}

      {:ok, index_case} ->
        :telemetry.execute([:loader, :commcare, :updated_from_commcare], %{count: 1})
        Logger.info("[#{__MODULE__}] updating case_id=#{index_case.case_id} in commcare domain=#{domain}")
        index_case |> Commcare.save_event("updated_from_commcare")
        {:update, index_case}
    end
  end

  defp maybe_update_index_case(index_case, :not_found, _, domain) do
    Logger.info("[#{__MODULE__}] creating case case_id=#{index_case.case_id} in commcare domain=#{domain}")
    {:create, index_case}
  end

  defp post_case(xml, domain, case_id) do
    if commcare_enabled?() do
      {xml, Commcare.Api.post_case(xml, domain)}
    else
      Logger.info("[#{__MODULE__}] not posting case_id=#{case_id} domain=#{domain} to commcare due to feature flag")
      {xml, {:ok, %{status_code: 900, body: "Sending to CommCare is not enabled"}}}
    end
  end

  defp record_commcare_response({xml, {:ok, response}}, index_case, timestamp, action, _diff_summary, _job) do
    Logger.info("[#{__MODULE__}] recording case case_id=#{index_case.case_id} as successfully sent to commcare")
    :telemetry.execute([:loader, :commcare, action], %{count: 1})
    {:ok, _event} = save_event(index_case, xml, response.body, "send_to_commcare_succeeded", timestamp, action)
    :ok
  end

  defp record_commcare_response({xml, {:error, %{body: response_body}}}, index_case, timestamp, action, diff_summary, job) do
    :telemetry.execute([:loader, :commcare, :api_error], %{count: 1})
    record_commcare_response({xml, {:error, response_body}}, index_case, timestamp, action, diff_summary, job)
  end

  defp record_commcare_response({xml, {:error, response}}, index_case, timestamp, action, _diff_summary, job) do
    ErrorReporter.post_to_sentry(inspect(response), job)
    Logger.error("[#{__MODULE__}] recording case case_id=#{index_case.case_id} as failed to send to commcare")
    {:ok, _event} = save_event(index_case, xml, response, "send_to_commcare_failed", timestamp, action)
    {:error, response}
  end

  defp save_event(%Commcare.IndexCase{} = index_case, xml, response, event_name, timestamp, action) do
    Commcare.save_event(index_case,
      type: event_name,
      stash: xml,
      data: %{action: action, response: response, timestamp: timestamp}
    )
  end

  defp report_transfer_target_not_found(case_id, domain) do
    :telemetry.execute([:loader, :commcare, :transfer, :not_found], %{count: 1})
    message = "Commcare case case_id=#{case_id} county_domain=#{domain} was transferred but target case was not found"
    Logger.error("[#{__MODULE__}] #{message}")
    message
  end

  defp report_rate_limited(case_id, county_id) do
    :telemetry.execute([:loader, :commcare, :rate_limited], %{count: 1})
    Logger.error("[#{__MODULE__}] Snoozing worker for case_id=#{case_id}, county_id=#{county_id}")
  end

  defp report_index_case_rerouted(index_case, destination_index_case) do
    Commcare.save_event(index_case,
      type: "send_to_commcare_rerouted",
      data: %{
        reason: "Update for this case sent to another case due to county transfer",
        destination_index_case_id: destination_index_case.id,
        destination_case_id: destination_index_case.case_id,
        destination_county_id: destination_index_case.county_id
      }
    )
  end

  defp report_cycle_detected(index_case) do
    :telemetry.execute([:loader, :commcare, :transfer, :cycle_detected], %{count: 1})
    Logger.error("[#{__MODULE__}] Discarded job for case_id=#{index_case.case_id}, county_id=#{index_case.county_id}")
    Commcare.save_event(index_case, type: "send_to_commcare_discarded", data: %{reason: "cycle_detected"})
  end

  defp report_non_specific_error do
    :telemetry.execute([:loader, :commcare, :error], %{count: 1})
  end

  defp commcare_enabled? do
    Application.get_env(:nys_etl, :commcare_posting_enabled, false)
  end
end
