defmodule NYSETL.Release do
  @moduledoc """
  Functions that can be called in an Elixir release to setup dependencies where Mix is not present.
  """

  require Logger

  @app :nys_etl
  def migrate do
    ensure_started()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    ensure_started()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Seed the database with known required data.

  * County records, based on fips codes found in CommCare's county fixtures

  """
  def seed() do
    ensure_started()

    NYSETL.Commcare.County.all_counties(cache: :cache_disabled)
    |> Enum.each(fn %{"fips" => fips} ->
      Logger.info("[#{__MODULE__}] Find or create county: #{fips}")
      NYSETL.ECLRS.find_or_create_county(fips)
    end)
  end

  defp repos do
    Application.load(@app)
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp ensure_started do
    Application.put_env(:nys_etl, :start_viaduct_workers, false)
    Application.ensure_all_started(:ssl)
    Application.ensure_all_started(:nys_etl)
  end
end
