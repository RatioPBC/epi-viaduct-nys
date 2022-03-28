defmodule NYSETL.Engines.E5.PollingConfigTest do
  use NYSETL.DataCase, async: false

  alias NYSETL.Engines.E5.PollingConfig

  setup do
    {:ok, true} = FunWithFlags.enable(:commcare_case_forwarder)
    :ok
  end

  test "enable / disable a domain" do
    {:ok, _} = start_supervised(PollingConfig)

    assert PollingConfig.enabled?("a-domain")
    assert PollingConfig.enabled?("another-domain")

    assert :ok = PollingConfig.disable("a-domain")
    refute PollingConfig.enabled?("a-domain")
    assert PollingConfig.enabled?("another-domain")

    assert :ok = PollingConfig.enable("a-domain")
    assert PollingConfig.enabled?("a-domain")
  end

  test "read domains list to exclude from app config" do
    domains_to_exclude = Application.fetch_env(:nys_etl, :e5_domains_to_exclude)

    on_exit(fn ->
      case domains_to_exclude do
        :error -> Application.delete_env(:nys_etl, :e5_domains_to_exclude)
        _ -> Application.put_env(:nys_etl, :e5_domains_to_exclude, domains_to_exclude)
      end
    end)

    Application.put_env(:nys_etl, :e5_domains_to_exclude, ["a-domain"])
    {:ok, _} = start_supervised(PollingConfig)

    refute PollingConfig.enabled?("a-domain")
    assert PollingConfig.enabled?("another-domain")
  end

  test "always enabled when :commcare_case_forwarder is off" do
    {:ok, _} = start_supervised(PollingConfig)

    assert :ok = PollingConfig.disable("a-domain")
    refute PollingConfig.enabled?("a-domain")

    {:ok, false} = FunWithFlags.disable(:commcare_case_forwarder)

    assert PollingConfig.enabled?("a-domain")
  end
end
