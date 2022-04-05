defmodule NYSETLWeb.Router do
  use NYSETLWeb, :router

  import Phoenix.LiveDashboard.Router
  import Plug.BasicAuth, only: [basic_auth: 2]
  import Oban.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {NYSETLWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :basic_auth, username: "commcare", password: Application.compile_env(:nys_etl, :commcare_case_forwarder_password)
  end

  pipeline :protected do
    plug :dashboard_basic_auth
  end

  scope "/", NYSETLWeb do
    pipe_through :browser

    live "/", PageLive, :index
    get("/healthcheck", HealthCheckController, :index)
  end

  # Other scopes may use custom stacks.
  scope "/api", NYSETLWeb do
    pipe_through :api

    get "/commcare_cases", CommcareCasesController, :index
    post "/commcare_cases", CommcareCasesController, :create
  end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).

  scope "/admin" do
    pipe_through [:browser, :protected]
    live_dashboard("/dashboard", metrics: NYSETLWeb.Telemetry)
    oban_dashboard("/oban")
  end

  def dashboard_basic_auth(conn, _opts) do
    Plug.BasicAuth.basic_auth(
      conn,
      username: Application.get_env(:nys_etl, :basic_auth)[:dashboard_username],
      password: Application.get_env(:nys_etl, :basic_auth)[:dashboard_password]
    )
  end
end
