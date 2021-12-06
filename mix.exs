defmodule NYSETL.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      aliases: aliases(),
      app: :nys_etl,
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      deps: deps(),
      docs: docs(),
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      releases: releases(),
      start_permanent: [:prod, :dry_run] |> Enum.member?(Mix.env()),
      version: @version
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {NYSETL.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  # local_or_remote(:remote, :nys_etl_dashboard, version: "~> 1.0", organization: "geometer", path: "../nys-etl-dashboard"),

  defp deps do
    [
      local_or_remote(:remote, :euclid, version: "~> 0.1", path: "../euclid"),
      {:briefly, "~> 0.3"},
      {:broadway, "~> 1.0"},
      {:cachex, "~> 3.2"},
      {:configparser_ex, "~> 4.0"},
      {:credo, "~> 1.4", only: [:dev, :test], runtime: false},
      {:earmark, "~> 1.4"},
      {:ecto_sql, "~> 3.7"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_sqs, "~> 3.2"},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_doc, "~> 0.21", runtime: false},
      {:faker, "~> 0.13", only: [:dev, :test]},
      {:floki, "~> 0.29", only: :test},
      {:flow, "~> 1.0"},
      {:gestalt, "~> 1.0"},
      {:gettext, "~> 0.11"},
      {:httpoison, "~> 1.7"},
      {:jason, "~> 1.0"},
      {:licensir, "~> 0.6", only: :dev, runtime: false},
      {:logger_file_backend, "~> 0.0.11"},
      {:magritte, "~> 0.1.2"},
      {:mix_audit, "~> 1.0"},
      {:mox, "~> 1.0", only: :test},
      {:nimble_csv, "~> 1.1"},
      {:oban, "~> 2.3.4"},
      {:oban_pro, "~> 0.5", organization: "oban"},
      {:oban_web, "~> 2.3", organization: "oban"},
      {:paper_trail, "~> 0.14"},
      {:phoenix, "~> 1.5"},
      {:phoenix_ecto, "~> 4.1"},
      {:phoenix_html, "~> 2.14"},
      {:phoenix_live_dashboard, "~> 0.2"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.13"},
      {:plug_cowboy, "~> 2.0"},
      {:postgrex, "~> 0.15.8"},
      {:saxy, "~> 1.2"},
      {:sentry, "~> 8.0"},
      {:telemetry_metrics, "~> 0.4"},
      {:telemetry_metrics_cloudwatch, "~> 0.3"},
      {:telemetry_poller, "~> 0.4"},
      {:timex, "~> 3.7"},
      {:xml_builder, "~> 2.1"},
      {:yaml_elixir, "~> 2.4"},
      {:zipcode, "> 0.0.0", git: "https://gitlab.com/geometerio/zipcode"}
    ]
  end

  defp docs() do
    [
      api_reference: false,
      main: "overview",
      assets: "guides/assets",
      extra_section: "GUIDES",
      extras: extras(),
      formatters: ["html"],
      source_url: "https://github.com/RatioPBC/epi-viaduct-nys",
      main: "overview",
      nest_modules_by_prefix: [
        NYSETL.Backfillers,
        NYSETL.Commcare,
        NYSETL.ECLRS,
        NYSETL.Engines.E1,
        NYSETL.Engines.E2,
        NYSETL.Engines.E3,
        NYSETL.Engines.E4,
        NYSETL.Engines.E5,
        NYSETL.Extra,
        NYSETL.Monitoring,
        NYSETL.Tasks,
        NYSETLWeb
      ]
    ]
  end

  defp extras() do
    ~w{
      guides/overview.md
      guides/engines.md
      guides/performance.md
      guides/integration_testing.md
    }
  end

  defp local_or_remote(:local, package, options) do
    {
      package,
      options
      |> Keyword.delete(:organization)
      |> Keyword.delete(:version)
    }
  end

  defp local_or_remote(:remote, package, options) do
    {
      package,
      options |> Keyword.get(:version),
      options
      |> Keyword.delete(:path)
      |> Keyword.delete(:version)
    }
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "cmd npm install --prefix assets"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", &compile_assets/1, "test"]
    ]
  end

  defp compile_assets(_) do
    Mix.shell().cmd("npm run build --prefix assets", quiet: true)
  end

  def releases() do
    include_executables =
      case :os.type() do
        {:win32, :nt} -> [:windows]
        _ -> [:unix]
      end

    [
      nys_etl: [
        applications: [runtime_tools: :permanent],
        include_executables_for: include_executables,
        steps: [:assemble]
      ]
    ]
  end
end
