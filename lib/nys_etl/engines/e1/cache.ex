defmodule NYSETL.Engines.E1.Cache do
  @moduledoc """
  Wrapper for Cachex, providing a large number of checksum caches under a supervision
  tree. While Cachex provides non-blocking reads and writes for caches, transactions
  for a specific cache block other transactions via a single GenServer message queue.

  This supervision tree improves the concurrency of transactions by providing a cache ring
  of N caches, using `:erlang.phash2/2` to deterministically assign each checksum to a
  member of the ring.
  """

  use Supervisor

  defdelegate get(cache, key), to: Cachex

  ## Cache functions

  def clear() do
    cache_count_range() |> Enum.each(fn x -> Cachex.clear(:"checksum_#{x}") end)
    :ok
  end

  def dump(path) do
    cache_count_range()
    |> Enum.each(fn x ->
      Cachex.dump(:"checksum_#{x}", Path.join(path, "checksum_#{x}"))
    end)
  end

  def load(path) do
    cache_count_range()
    |> Enum.each(fn x ->
      Cachex.load(:"checksum_#{x}", Path.join(path, "checksum_#{x}"))
    end)
  end

  def get(checksum) do
    checksum
    |> cache_for()
    |> get(checksum)
  end

  def put!(cache, checksum, value) do
    cache
    |> Cachex.put!(checksum, value)
  end

  def put!(checksum, value) do
    checksum
    |> cache_for()
    |> put!(checksum, value)
  end

  def transaction(checksum, fun) when is_function(fun) do
    cache_for(checksum)
    |> Cachex.transaction!([checksum], fun)
  end

  ## Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  ## Callbacks

  @impl true
  def init(_init_arg) do
    children =
      cache_count_range()
      |> Enum.map(fn cache ->
        Supervisor.child_spec({Cachex, :"checksum_#{cache}"}, id: {Cachex, :"checksum_#{cache}"})
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end

  ## Private

  defp cache_count(), do: System.schedulers() * 3
  defp cache_count_range(), do: 0..(cache_count() - 1)
  defp cache_for(checksum), do: :"checksum_#{:erlang.phash2(checksum, cache_count())}"
end
