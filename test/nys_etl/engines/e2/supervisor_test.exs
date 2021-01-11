defmodule NYSETL.Engines.E2.SupervisorTest do
  use NYSETL.DataCase, async: false

  describe "start_link" do
    test "successfully starts its supervision tree" do
      {:ok, _pid} = start_supervised(NYSETL.Engines.E2.Supervisor)
      stop_supervised(NYSETL.Engines.E2.Supervisor)
    end
  end
end
