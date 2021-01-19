defmodule NYSETL.Commcare.CountiesCache do
  use GenServer
  require Logger

  defstruct source: nil, ttl: 30 * 60 * 1000, retry_interval: 60 * 1000, timeout: 5 * 1000, cached: :not_set, error_count: 0

  @type t :: %NYSETL.Commcare.CountiesCache{
          source: function(),
          ttl: pos_integer(),
          retry_interval: pos_integer(),
          timeout: timeout(),
          cached: any(),
          error_count: non_neg_integer()
        }

  @spec new(any) :: t()
  def new(attrs), do: __struct__(attrs)

  @spec start_link(function(), keyword) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(source, opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, {source, opts}, name: name)
  end

  @spec init({function(), keyword}) :: {:ok, NYSETL.Commcare.CountiesCache.t()}
  def init({source, opts}) do
    GenServer.cast(self(), :initiate_cache)
    state = new([source: source] ++ Keyword.take(opts, [:ttl, :retry_interval, :timeout]))
    {:ok, state}
  end

  def handle_cast(:initiate_cache, %__MODULE__{source: source, ttl: ttl} = state) do
    {:ok, value} = source.()
    Process.send_after(self(), :refresh_cache, ttl)
    {:noreply, %{state | cached: value}}
  end

  def handle_cast({:refresh_cache, what}, state) do
    case what do
      {:ok, value} ->
        Process.send_after(self(), :refresh_cache, state.ttl)
        {:noreply, %{state | cached: value, error_count: 0}}

      {:error, msg} ->
        Logger.warn(mod: __MODULE__, fun: :refresh_cache, msg: msg)
        Process.send_after(self(), :refresh_cache, state.retry_interval)
        {:noreply, %{state | error_count: state.error_count + 1}}
    end
  end

  def handle_info(:refresh_cache, %__MODULE__{source: source, timeout: timeout} = state) do
    parent = self()
    Task.start(fn -> refresh_task(parent, source, timeout) end)
    {:noreply, state}
  end

  @spec refresh_task(atom | pid | {atom, any} | {:via, atom, any}, any, :infinity | non_neg_integer) :: :ok
  def refresh_task(server, source, timeout) do
    task = Task.async(fn -> source.() end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> GenServer.cast(server, {:refresh_cache, result})
      nil -> GenServer.cast(server, {:refresh_cache, {:error, "No result in #{timeout}ms"}})
    end
  end

  @spec get(atom | pid | {atom, any} | {:via, atom, any}) :: any
  def get(name \\ __MODULE__) do
    GenServer.call(name, :cached)
  end

  def handle_call(:cached, _from, %__MODULE__{cached: cached} = state) do
    {:reply, cached, state}
  end
end
