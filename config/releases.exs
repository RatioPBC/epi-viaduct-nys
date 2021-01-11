# In this file, we load production configuration and secrets
# from environment variables. You can also hardcode secrets,
# although such is generally not recommended and you have to
# remember to add this file to your .gitignore.
import Config

if secrets = System.get_env("SECRETS") do
  secrets
  |> Jason.decode!()
  |> Enum.each(fn {key, value} ->
    System.put_env(key, value)
  end)
end

defmodule CFG do
  def to_boolean("true"), do: true
  def to_boolean(_), do: false

  def application_port(), do: String.to_integer(System.get_env("PORT", "4000"))
  def canonical_host(), do: System.fetch_env!("CANONICAL_HOST")
  def dashboard_username(), do: System.fetch_env!("DASHBOARD_USERNAME")
  def dashboard_password(), do: System.fetch_env!("DASHBOARD_PASSWORD")
  def live_view_signing_salt(), do: System.fetch_env!("LIVE_VIEW_SIGNING_SALT")
  def secret_key_base(), do: System.fetch_env!("SECRET_KEY_BASE")
  def start_viaduct_workers?(), do: System.get_env("ENABLE_VIADUCT_WORKERS", "false") == "true"

  def database_url() do
    case System.fetch_env("DATABASE_SECRET") do
      :error -> System.fetch_env!("DATABASE_URL")
      {:ok, "postgres://" <> _ = url} -> url
      {:ok, "{" <> _ = secret} -> secret |> Jason.decode!() |> to_url()
    end
  end

  def to_url(%{"username" => user, "password" => pass, "host" => host, "port" => port, "dbname" => dbname}) do
    "ecto://#{user}:#{pass}@#{host}:#{port}/#{dbname}"
  end
end

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

config :ex_aws,
  access_key_id: AwsConfig.config("AWS_ACCESS_KEY_ID"),
  json_codec: Jason,
  region: AwsConfig.region(),
  secret_access_key: AwsConfig.config("AWS_SECRET_ACCESS_KEY")

config :nys_etl,
  commcare_api_key_credentials: System.fetch_env!("COMMCARE_API_KEY_CREDENTIALS"),
  commcare_base_url: System.fetch_env!("COMMCARE_BASE_URL"),
  commcare_root_domain: System.fetch_env!("COMMCARE_ROOT_DOMAIN"),
  commcare_username: System.fetch_env!("COMMCARE_USERNAME"),
  commcare_user_id: System.fetch_env!("COMMCARE_USER_ID"),
  county_list_cache_enabled: true,
  ecto_repos: [NYSETL.Repo],
  environment_name: String.to_atom(System.fetch_env!("ENVIRONMENT") |> String.downcase()),
  http_client: HTTPoison,
  namespace: NYSETL,
  sqs_queue_url: System.get_env("VIADUCT_SQS_QUEUE_URL"),
  start_viaduct_workers: CFG.start_viaduct_workers?()

config :nys_etl, :basic_auth,
  dashboard_username: CFG.dashboard_username(),
  dashboard_password: CFG.dashboard_password()

config :nys_etl, NYSETL.Repo,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: CFG.to_boolean(System.get_env("DBSSL", "true")),
  url: CFG.database_url()

config :nys_etl, NYSETLWeb.Endpoint,
  http: [
    port: CFG.application_port(),
    transport_options: [socket_opts: [:inet6]]
  ],
  live_view: [signing_salt: CFG.live_view_signing_salt()],
  secret_key_base: CFG.secret_key_base(),
  server: true,
  url: [
    host: CFG.canonical_host(),
    port: CFG.application_port(),
    scheme: "http"
  ]
