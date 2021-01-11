defmodule NYSETL.SimpleCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Euclid.Test.Extra.Assertions
      import ExUnit.Assertions
      import NYSETL.Test.Extra.Assertions

      alias NYSETL.Test
    end
  end
end
