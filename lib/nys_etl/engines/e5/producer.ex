defmodule NYSETL.Engines.E5.Producer do
  use GenStage

  require Logger

  @status_running :running
  @status_halted :halted
  @enforce_keys ~w{full_county_list idle_timeout_ms current_county_list}a
  defstruct [
    :current_county,
    :current_county_list,
    :full_county_list,
    :idle_timeout_ms,
    :last_offset,
    :modified_since,
    :most_recent_demand_at,
    backlog: [],
    status: @status_running
  ]

  def new(attrs \\ []), do: __struct__(attrs)

  def init(opts) do
    start_date = Keyword.get(opts, :start_date)
    counties = Keyword.fetch!(opts, :county_list)
    idle_timeout_ms = Keyword.get(opts, :idle_timeout_ms, 300_000)

    :timer.send_interval(500, self(), :poll)

    {:producer,
     new(
       full_county_list: counties,
       idle_timeout_ms: idle_timeout_ms,
       modified_since: start_date,
       current_county_list: counties
     )}
  end

  def handle_info(:poll, state) do
    state.most_recent_demand_at
    |> DateTime.compare(now() |> DateTime.add(-state.idle_timeout_ms, :millisecond))
    |> case do
      :lt ->
        handle_demand(10, %{state | status: @status_running})

      _ ->
        :telemetry.execute([:extractor, :commcare, :produced], %{count: 0})
        {:noreply, [], state}
    end
  end

  @doc """
  `handle_demand/2` is called when the Broadway dispatcher sees that consumers are free
  to receive more messages.

  This module iterates through counties in the `current_county_list` until it runs out of
  counties, at which point it goes to sleep. After being asleep `idle_timeout_ms`, the `:poll`
  timer will wake this producer up, at which point it will start over from the top of the
  county list.

  Special cases in the function heads below:
  * backlog has message count greater than demand : A previous API request has put CommCare
    cases into a backlog, and we can drain the backlog without making another API request.
  * is_nil(last_offset) : The last API request for the current county is the last page of
    records that have been updated recently. Move on to the next county.

  Error handling:
  * If an error is observed when making a CommCare API request, recurse into the
    `is_nil(last_offset)` special case so that we immediately move on to the next county.
  """
  def handle_demand(_demand, %{status: @status_halted} = state) do
    {:noreply, [], state}
  end

  def handle_demand(demand, %{backlog: backlog} = state) when length(backlog) > demand do
    {taken, rest} = Enum.split(backlog, demand)

    Logger.debug("[#{__MODULE__}] pulling from backlog, taking=#{length(taken)}, backlog=#{length(rest)}")
    :telemetry.execute([:extractor, :commcare, :produced], %{count: length(taken)})

    {:noreply, taken,
     state
     |> with_most_recent_demand_at()
     |> with_backlog(rest)}
  end

  def handle_demand(demand, %{last_offset: nil} = state) do
    state
    |> next_county()
    |> case do
      {:halt, new_state} -> {:noreply, state.backlog, with_backlog(new_state, []), :hibernate}
      {:ok, new_state} -> handle_demand(demand, new_state)
    end
  end

  def handle_demand(demand, %{backlog: backlog} = state) do
    current = state.current_county

    NYSETL.Commcare.Api.get_cases(
      county_domain: current.domain,
      limit: 100,
      offset: state.last_offset,
      type: "patient",
      full: true,
      modified_since: state.modified_since
    )
    |> case do
      {:ok, %{"next_offset" => next_offset, "objects" => cases}} ->
        cases_with_county = zip(cases, state.current_county)
        {taken, rest} = Enum.split(backlog ++ cases_with_county, demand)

        Logger.debug("[#{__MODULE__}] found cases count=#{length(cases)}, taking=#{length(taken)}, backlog=#{length(rest)}")
        :telemetry.execute([:extractor, :commcare, :produced], %{count: length(taken)})

        {:noreply, taken,
         state
         |> with_most_recent_demand_at()
         |> with_offset(next_offset)
         |> with_backlog(rest)}

      {:error, reason} ->
        Logger.error("[#{__MODULE__}] error fetching cases from CommCare, reason=#{inspect(reason)}")
        handle_demand(demand, %{state | last_offset: nil})
    end
  end

  defp now(), do: DateTime.utc_now()

  defp next_county(%__MODULE__{} = state) do
    state.current_county_list
    |> case do
      [next | rest] ->
        Logger.debug("[#{__MODULE__}] extracting domain=#{next.domain}")

        {:ok,
         %{
           state
           | current_county: next,
             current_county_list: rest,
             last_offset: 0
         }}

      [] ->
        {:halt,
         %{
           state
           | current_county_list: state.full_county_list,
             last_offset: 0,
             modified_since: Date.utc_today(),
             status: @status_halted
         }}
    end
  end

  defp with_backlog(state, cases), do: %{state | backlog: cases}
  defp with_most_recent_demand_at(state), do: %{state | most_recent_demand_at: now()}
  defp with_offset(state, offset), do: %{state | last_offset: offset}

  defp zip(cases, county) do
    cases
    |> Enum.map(&[case: &1, county: county])
  end
end
