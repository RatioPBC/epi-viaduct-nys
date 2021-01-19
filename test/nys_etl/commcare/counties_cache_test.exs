defmodule NYSETL.Commcare.CountiesCacheTest do
  use NYSETL.DataCase, async: true

  import ExUnit.CaptureLog

  setup :mock_county_list

  alias NYSETL.Commcare.CountiesCache

  @testparams [ttl: 5, retry_interval: 1]

  setup do
    %{
      value: :rand.uniform(10_000_000),
      name: :"cache_#{:rand.uniform(10_000_000)}"
    }
  end

  test "it fetches the initial value on init (async)", context do
    fun = fn -> {:ok, context.value} end
    {:ok, pid} = CountiesCache.start_link(fun, [name: context.name] ++ @testparams)
    assert CountiesCache.get(pid) == context.value
  end

  test "the cache updates every now and then", context do
    {:ok, counter} = Agent.start(fn -> context.value end)

    fun = fn ->
      value = Agent.get(counter, fn n -> n end)
      Agent.update(counter, fn n -> n + 1 end)
      {:ok, value}
    end

    {:ok, pid} = CountiesCache.start_link(fun, [name: context.name] ++ @testparams)
    assert CountiesCache.get(pid) == context.value
    # Sleep for longer than the ttl (5)
    Process.sleep(10)
    assert CountiesCache.get(pid) > context.value
  end

  test "the cache delivers stale data when it cannot be refreshed", context do
    {:ok, unstable_service} = Agent.start(fn -> :responsive end)

    fun = fn ->
      Agent.get(unstable_service, fn n -> n end)
      |> case do
        :responsive ->
          Agent.update(unstable_service, fn _ -> :unavailable end)
          {:ok, context.value}

        :unavailable ->
          {:error, "Service unavailable"}
      end
    end

    log =
      capture_log(fn ->
        {:ok, pid} = CountiesCache.start_link(fun, [name: context.name] ++ @testparams)
        assert CountiesCache.get(pid) == context.value
        Process.sleep(10)
        assert CountiesCache.get(pid) == context.value
      end)

    assert log =~ "Service unavailable"
  end

  test "the cache refresh is async", context do
    {:ok, unstable_service} = Agent.start(fn -> 0 end)

    fun = fn ->
      value = Agent.get(unstable_service, fn n -> n end)
      Agent.update(unstable_service, fn n -> n + 1 end)

      case value do
        0 ->
          {:ok, context.value}

        _ ->
          Process.sleep(20)
          {:ok, context.value + 1}
      end
    end

    {:ok, pid} = CountiesCache.start_link(fun, [name: context.name] ++ @testparams)
    assert CountiesCache.get(pid) == context.value
    # Sleep for longer than the ttl (5)
    Process.sleep(10)
    # The updating process is hanging on the `sleep(20)` above so the value hasn't changed
    assert CountiesCache.get(pid) == context.value
    # Let the updating process finish
    Process.sleep(20)
    assert CountiesCache.get(pid) > context.value
  end

  test "the cache refresh has a timeout", context do
    {:ok, unstable_service} = Agent.start(fn -> 0 end)

    fun = fn ->
      value = Agent.get(unstable_service, fn n -> n end)
      Agent.update(unstable_service, fn n -> n + 1 end)

      case value do
        0 ->
          {:ok, context.value}

        _ ->
          Process.sleep(20)
          {:ok, context.value + 1}
      end
    end

    log =
      capture_log(fn ->
        {:ok, pid} = CountiesCache.start_link(fun, [name: context.name, timeout: 10] ++ @testparams)
        assert CountiesCache.get(pid) == context.value
        # Sleep for longer than the ttl (5) and the updater's processing time (20)
        Process.sleep(40)
        # The updater is too slow, so the value never updates
        assert CountiesCache.get(pid) == context.value
      end)

    assert log =~ "No result in 10ms"
  end
end
