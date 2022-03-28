defmodule NYSETL.Engines.E5.PollingConfig do
  use Agent

  def start_link(_) do
    # according to the OTP docs, this isn't really the right place
    # to read application config. But this whole thing is intended to be
    # temporary and removed after we switch to case forwarder
    domains_to_exclude =
      Application.get_env(:nys_etl, :e5_domains_to_exclude, [])
      |> MapSet.new()

    Agent.start_link(fn -> domains_to_exclude end, name: __MODULE__)
  end

  def enabled?(domain) do
    !FunWithFlags.enabled?(:commcare_case_forwarder) || Agent.get(__MODULE__, &(!MapSet.member?(&1, domain)))
  end

  def disable(domain) do
    Agent.update(__MODULE__, &MapSet.put(&1, domain))
  end

  def enable(domain) do
    Agent.update(__MODULE__, &MapSet.delete(&1, domain))
  end
end
