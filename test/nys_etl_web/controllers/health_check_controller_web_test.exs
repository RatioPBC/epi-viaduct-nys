defmodule NYSETLWeb.HealthCheckControllerTest do
  use NYSETLWeb.ConnCase, async: true

  describe "index" do
    test "is ok", context do
      conn = get(context.conn, Routes.health_check_path(@endpoint, :index))
      assert text_response(conn, 200) =~ "OK"
    end
  end
end
