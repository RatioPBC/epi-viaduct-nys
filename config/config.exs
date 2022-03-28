# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

defmodule AwsConfig do
  def config(env_variable, profile \\ System.get_env("AWS_PROFILE"))
  def config(env_variable, nil), do: [{:system, env_variable}, :instance_role]

  def config(env_variable, profile),
    do: [{:system, env_variable}, {:awscli, profile, 30}, :instance_role]

  def region() do
    System.get_env(
      "AWS_REGION",
      System.get_env("AWS_DEFAULT_REGION", "us-east-1")
    )
  end
end

defmodule SentryConfig do
  def ca_bundle() do
    System.get_env("SENTRY_CA_BUNDLE")
  end

  def hackney_opts(bundle \\ ca_bundle())
  def hackney_opts(nil), do: []
  def hackney_opts(cert) when is_binary(cert), do: [ssl_options: [cacertfile: cert]]
end

config :ex_aws,
  access_key_id: AwsConfig.config("AWS_ACCESS_KEY_ID"),
  json_codec: Jason,
  region: AwsConfig.region(),
  secret_access_key: AwsConfig.config("AWS_SECRET_ACCESS_KEY")

config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: NYSETL.Repo

# disable cache_bust_notifications since this runs on a single node
config :fun_with_flags, :cache_bust_notifications, enabled: false

config :nys_etl,
  cloudwatch_metrics_enabled: true,
  commcare_api_key_credentials: System.get_env("COMMCARE_API_KEY_CREDENTIALS"),
  commcare_base_url: System.get_env("COMMCARE_BASE_URL"),
  commcare_posting_enabled: System.get_env("COMMCARE_POSTING_ENABLED") == "true",
  commcare_root_domain: System.get_env("COMMCARE_ROOT_DOMAIN"),
  commcare_username: System.get_env("COMMCARE_USERNAME"),
  commcare_user_id: System.get_env("COMMCARE_USER_ID"),
  county_list: [],
  county_list_cache_enabled: true,
  e5_producer_module: NYSETL.Engines.E5.Producer,
  eclrs_ignore_before_timestamp: ~U[2020-06-28 00:00:00Z],
  ecto_repos: [NYSETL.Repo],
  environment_name: String.to_atom(System.get_env("ENVIRONMENT", "dev") |> String.downcase()),
  http_client: HTTPoison,
  namespace: NYSETL,
  oban_error_reporter_attempt_threshold: 4,
  start_viaduct_workers: true,
  use_commcare_county_list: false,
  sqs_queue_url: System.get_env("VIADUCT_SQS_QUEUE_URL")

# Configures the endpoint
config :nys_etl, NYSETLWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "5ESialh6gsRG10mbViRqfjMd7c2B4SkGsVzc2NLhCnKmLwS8pODMEwoLJGrBcFH3",
  render_errors: [view: NYSETLWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: NYSETL.PubSub,
  live_view: [signing_salt: "xwI4AjtR"]

config :logger,
  backends: [
    :console,
    {LoggerFileBackend, :debug_log_file},
    {LoggerFileBackend, :info_log_file},
    {LoggerFileBackend, :error_log_file},
    Sentry.LoggerBackend
  ],
  utc_log: true

config :logger, :debug_log_file,
  format: "$dateT$timeZ $metadata[$level] $message\n",
  level: :debug,
  path: "/var/log/viaduct/debug.log"

config :logger, :info_log_file,
  format: "$dateT$timeZ $metadata[$level] $message\n",
  level: :info,
  path: "/var/log/viaduct/info.log"

config :logger, :error_log_file,
  format: "$dateT$timeZ $metadata[$level] $message\n",
  level: :warn,
  path: "/var/log/viaduct/error.log"

config :logger, :console,
  format: "$dateT$timeZ $metadata[$level] $message\n",
  metadata: [:request_id]

config :nys_etl, Oban,
  engine: Oban.Pro.Queue.SmartEngine,
  repo: NYSETL.Repo,
  queues: [default: 10, commcare: 10, backfillers: 10, eclrs: 10],
  plugins: [
    Oban.Plugins.Gossip,
    Oban.Pro.Plugins.BatchManager,
    Oban.Pro.Plugins.Lifeline,
    Oban.Web.Plugins.Stats
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :sentry,
  dsn: {:system, "SENTRY_DSN"},
  environment_name: String.to_atom(System.get_env("ENVIRONMENT", "dev") |> String.downcase()),
  included_environments: [:prod, :dev],
  enable_source_code_context: true,
  root_source_code_path: File.cwd!(),
  hackney_opts: SentryConfig.hackney_opts()

config :paper_trail,
  repo: NYSETL.Repo

config :hackney,
  use_default_pool: false

config :nys_etl, :extra_county_list, [
  %{
    "county_display" => "DOH special 905 -- county assign, manual (address missing)",
    "fips" => "905",
    "participating" => "no"
  },
  %{
    "county_display" => "DOH special 907 -- geocode (county assign, automatic)",
    "fips" => "907",
    "participating" => "no"
  }
]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
