defmodule NYSETL.Engines.E5.PollingConfigTest do
  use NYSETL.DataCase, async: false

  alias NYSETL.Engines.E5.PollingConfig

  describe "enabled?" do
    setup :fwf_case_forwarder

    test "enable / disable a domain" do
      assert PollingConfig.enabled?("a-domain")
      assert PollingConfig.enabled?("another-domain")

      assert :ok = PollingConfig.disable("a-domain")
      refute PollingConfig.enabled?("a-domain")
      assert PollingConfig.enabled?("another-domain")

      assert :ok = PollingConfig.enable("a-domain")
      assert PollingConfig.enabled?("a-domain")
    end

    test "always enabled when :commcare_case_forwarder is off" do
      assert :ok = PollingConfig.disable("a-domain")
      refute PollingConfig.enabled?("a-domain")

      {:ok, false} = FunWithFlags.disable(:commcare_case_forwarder)

      assert PollingConfig.enabled?("a-domain")
    end
  end

  test "read domains list to exclude from app config", context do
    domains_to_exclude = Application.fetch_env!(:nys_etl, :e5_domains_to_exclude)

    on_exit(fn ->
      Application.put_env(:nys_etl, :e5_domains_to_exclude, domains_to_exclude)
    end)

    Application.put_env(:nys_etl, :e5_domains_to_exclude, ["a-domain"])

    :ok = fwf_case_forwarder(context)

    refute PollingConfig.enabled?("a-domain")
    assert PollingConfig.enabled?("another-domain")
  end
end
