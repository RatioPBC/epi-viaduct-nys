defmodule NYSETL.Engines.E5.SupervisorTest do
  use NYSETL.DataCase, async: false

  import Mox
  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    NYSETL.HTTPoisonMock
    |> stub(:get, fn url, _, _ ->
      body =
        %{
          meta: %{},
          objects: []
        }
        |> Jason.encode!()

      {:ok, %{body: body, status_code: 200, request_url: url}}
    end)

    :ok
  end

  describe "start_link" do
    test "successfully starts its supervision tree" do
      {:ok, _pid} = start_supervised(NYSETL.Engines.E5.Supervisor)
      stop_supervised(NYSETL.Engines.E5.Supervisor)
    end
  end
end
