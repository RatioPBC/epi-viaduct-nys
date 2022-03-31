defmodule NYSETL.Test.MessageCollector do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def messages() do
    Agent.get(__MODULE__, & &1)
  end

  def add(message) do
    Agent.update(__MODULE__, &(&1 ++ [message]))
  end
end
