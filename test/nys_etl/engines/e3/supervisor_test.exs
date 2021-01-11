defmodule NYSETL.Engines.E3.SupervisorTest do
  use NYSETL.DataCase, async: false

  describe "start_link" do
    test "successfully starts its supervision tree" do
      {:ok, _pid} = start_supervised(NYSETL.Engines.E3.Supervisor)
      stop_supervised(NYSETL.Engines.E3.Supervisor)
    end
  end
end
