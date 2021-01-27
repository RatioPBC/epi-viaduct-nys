defmodule NYSETL.Commcare.CountiesCache do
  require Logger

  @spec start_link(keyword) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts), do: __MODULE__.Server.start_link(opts)

  @spec get(atom | pid | {atom, any} | {:via, atom, any}) :: any
  def get(name \\ __MODULE__) do
    GenServer.call(name, :cached)
  end

  defmodule Server do
    use GenServer
    defstruct source: nil, ttl: 30 * 60 * 1000, retry_interval: 60 * 1000, timeout: 5 * 1000, cached: :not_set, error_count: 0

    @type t :: %Server{
            source: function(),
            ttl: pos_integer(),
            retry_interval: pos_integer(),
            timeout: timeout(),
            cached: any(),
            error_count: non_neg_integer()
          }

    @spec new(any) :: t()
    def new(attrs), do: __struct__(attrs)

    @spec start_link(keyword) :: :ignore | {:error, any} | {:ok, pid}
    def start_link(opts) do
      Logger.info("[#{__MODULE__}] Starting CountiesCache")
      {name, opts} = Keyword.pop(opts, :name, __MODULE__)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    @spec init(keyword) :: {:ok, Server.t()} | {:stop, any()}
    def init(opts) do
      {:ok, source} = Keyword.fetch(opts, :source)
      state = new([source: source] ++ Keyword.take(opts, [:ttl, :retry_interval, :timeout]))
      task = Task.async(fn -> source.() end)

      case Task.yield(task, state.timeout) || Task.shutdown(task) do
        {:ok, {:ok, result}} ->
          Process.send_after(self(), :refresh_cache, state.ttl)
          {:ok, %{state | cached: result}}

        {:ok, {:error, reason}} ->
          {:stop, reason}

        nil ->
          {:stop, "No result in #{state.timeout}ms"}
      end
    end

    def handle_call(:cached, _from, %__MODULE__{cached: cached} = state) do
      {:reply, cached, state}
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
      __MODULE__.Refresher.refresh!(self(), source, timeout)
      {:noreply, state}
    end

    defmodule Refresher do
      @spec refresh!(pid(), function(), timeout()) :: {:ok, pid}
      def refresh!(server, source, timeout) do
        Task.start(fn -> refresh_task(server, source, timeout) end)
      end

      @spec refresh_task(atom | pid | {atom, any} | {:via, atom, any}, any, timeout()) :: :ok
      def refresh_task(server, source, timeout) do
        task = Task.async(fn -> source.() end)

        case Task.yield(task, timeout) || Task.shutdown(task) do
          {:ok, result} -> GenServer.cast(server, {:refresh_cache, result})
          nil -> GenServer.cast(server, {:refresh_cache, {:error, "No result in #{timeout}ms"}})
        end
      end
    end
  end
end
