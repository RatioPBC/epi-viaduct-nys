defmodule NYSETL.Test.Macros do
  defmacro step(description, do: block) do
    quote do
      Logger.info(unquote(description))
      unquote(block)
    end
  end
end
