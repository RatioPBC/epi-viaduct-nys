use Mix.Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
repo_opts =
  if socket_dir = System.get_env("PGDATA") do
    [socket_dir: socket_dir]
  else
    [username: "postgres", password: "postgres", hostname: System.get_env("POSTGRES_HOST", "localhost")]
  end

config :nys_etl,
       NYSETL.Repo,
       [
         database: "nys_etl_test#{System.get_env("MIX_TEST_PARTITION")}",
         # Just to make sure that the setting is accepted
         timeout: 16_000,
         pool: Ecto.Adapters.SQL.Sandbox
       ] ++ repo_opts

config :ex_aws,
  http_client: NYSETL.HTTPoisonMock,
  access_key_id: "test_access_key_id",
  secret_access_key: "test_secret_access_key"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :nys_etl, NYSETLWeb.Endpoint,
  http: [port: 4002],
  server: true

config :nys_etl,
  county_list: [
    %{
      "county_display" => "Midsomer",
      "county_name" => "midsomer",
      "domain" => "uk-midsomer-cdcms",
      "fips" => "1111",
      "gaz" => "ms-gaz",
      "location_id" => "a1a1a1a1a1",
      "participating" => "yes",
      "is_state_domain" => ""
    },
    %{
      "county_display" => "Yggdrasil",
      "county_name" => "yggdrasil",
      "domain" => "sw-yggdrasil-cdcms",
      "fips" => "9999",
      "gaz" => "ygg-gaz",
      "location_id" => "b2b2b2b22b2",
      "participating" => "yes",
      "is_state_domain" => ""
    },
    %{
      "county_display" => "Wilkes Land",
      "county_name" => "wilkes",
      "domain" => "aq-wilkes-cdcms",
      "fips" => "5678",
      "gaz" => "wlk-gaz",
      "location_id" => "",
      "participating" => "no",
      "is_state_domain" => ""
    },
    %{
      "county_display" => "UK Statewide",
      "county_name" => "statewide",
      "domain" => "uk-statewide-cdcms",
      "fips" => "1234",
      "gaz" => "state-gaz",
      "location_id" => "statewide-owner-id",
      "participating" => "yes",
      "is_state_domain" => "yes"
    }
  ]

config :nys_etl,
  ex_aws: NYSETL.ExAwsMock,
  cloudwatch_metrics_enabled: false,
  commcare_api_key_credentials: "test-api-key-credentials",
  commcare_base_url: "http://commcare.test.host",
  commcare_posting_enabled: true,
  commcare_root_domain: "ny-test-cdcms",
  commcare_user_id: "test-user-id",
  commcare_username: "test-username",
  county_list_cache_enabled: false,
  eclrs_ignore_before_timestamp: ~U[2020-03-01 00:00:00Z],
  environment_name: :test,
  http_client: NYSETL.HTTPoisonMock,
  oban_error_reporter_attempt_threshold: 0,
  start_viaduct_workers: false

config :logger, backends: [:console]
config :logger, level: :warn

config :nys_etl, Oban,
  repo: NYSETL.Repo,
  queues: [default: 1, commcare: 1],
  plugins: [
    Oban.Pro.Plugins.Lifeline,
    Oban.Web.Plugins.Stats
  ]

config :nys_etl, :sql_sandbox, true

config :sentry,
  environment_name: :test
