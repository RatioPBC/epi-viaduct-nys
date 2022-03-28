import Config

# For production, don't forget to configure the url host
# to something meaningful, Phoenix uses this information
# when generating URLs.
#
# Note we also include the path to a cache manifest
# containing the digested version of static files. This
# manifest is generated by the `mix phx.digest` task,
# which you should run after static files are built and
# before starting your production server.

# By default when starting the app in production, workers should not be started. This
# allows iex sessions to be started without picking up work. The system service must
# export "ENABLE_VIADUCT_WORKERS"="true".
start_phoenix_endpoint = System.get_env("ENABLE_PHX", "false") == "true"
start_viaduct_workers = System.get_env("ENABLE_VIADUCT_WORKERS", "false") == "true"

config :nys_etl, NYSETLWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  check_origin: false,
  http: [port: 4000],
  server: start_phoenix_endpoint,
  url: [host: {:system, "CANONICAL_HOST"}, port: {:system, "PORT"}]

config :nys_etl, :basic_auth,
  dashboard_username: System.get_env("DASHBOARD_USERNAME"),
  dashboard_password: System.get_env("DASHBOARD_PASSWORD")

config :nys_etl, NYSETL.Repo,
  show_sensitive_data_on_connection_error: false,
  pool_size: 100,
  timeout: 30_000,
  url: System.get_env("DATABASE_URL")

# TODO: do we need to send a different FIPS code for re-routed cases?
config :nys_etl,
  eclrs_ignore_before_timestamp: ~U[2020-07-13 00:00:00Z],
  commcare_posting_enabled: true,
  county_list: [],
  start_viaduct_workers: start_viaduct_workers,
  use_commcare_county_list: true,
  viaduct_commcare_user_ids: []

config :logger, level: System.get_env("LOG_LEVEL", "info") |> String.to_existing_atom()

config :nys_etl, Oban,
  engine: Oban.Pro.Queue.SmartEngine,
  repo: NYSETL.Repo,
  queues: [default: 10, commcare: 10, backfillers: 10, eclrs: 10],
  crontab: [
    {"* * * * *", NYSETL.Monitoring.Transformer.FailureReporter}
  ],
  plugins: [
    Oban.Plugins.Gossip,
    Oban.Pro.Plugins.BatchManager,
    Oban.Pro.Plugins.Lifeline,
    Oban.Web.Plugins.Stats
  ]

config :sentry,
  dsn: {:system, "SENTRY_DSN"},
  environment_name: String.to_atom(System.get_env("ENVIRONMENT", "prod") |> String.downcase()),
  included_environments: [:prod, :validation],
  enable_source_code_context: true,
  root_source_code_path: File.cwd!(),
  hackney_opts: SentryConfig.hackney_opts()

# ## SSL Support
#
# To get SSL working, you will need to add the `https` key
# to the previous section and set your `:url` port to 443:
#
#     config :nys_etl, NYSETLWeb.Endpoint,
#       ...
#       url: [host: "example.com", port: 443],
#       https: [
#         port: 443,
#         cipher_suite: :strong,
#         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
#         certfile: System.get_env("SOME_APP_SSL_CERT_PATH"),
#         transport_options: [socket_opts: [:inet6]]
#       ]
#
# The `cipher_suite` is set to `:strong` to support only the
# latest and more secure SSL ciphers. This means old browsers
# and clients may not be supported. You can set it to
# `:compatible` for wider support.
#
# `:keyfile` and `:certfile` expect an absolute path to the key
# and cert in disk or a relative path inside priv, for example
# "priv/ssl/server.key". For all supported SSL configuration
# options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
#
# We also recommend setting `force_ssl` in your endpoint, ensuring
# no data is ever sent via http, always redirecting to https:
#
#     config :nys_etl, NYSETLWeb.Endpoint,
#       force_ssl: [hsts: true]
#
# Check `Plug.SSL` for all available options in `force_ssl`.
