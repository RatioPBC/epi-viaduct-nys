defmodule NYSETL.Repo do
  @moduledoc """
  Callbacks and common additional functions for interacting with the NYSETL database.
  """

  use Ecto.Repo,
    otp_app: :nys_etl,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query

  @doc """
  Issue a count query on an `Ecto.Queryable`, which could be a schema module, or a `Ecto.Query`.

  ## Examples

      iex> NYSETL.ECLRS.TestResult |> NYSETL.Repo.count()
      0
  """
  @spec count(query :: Ecto.Queryable.t()) :: number()
  def count(query) do
    one!(from value in query, select: count("*"))
  end

  @doc """
  Return the first row from an `Ecto.Queryable`, which could be a schema module, or a `Ecto.Query`.
  Rows are ordered by `asc: :id` unless specified using the `:order_by` option.

  ## Examples

      iex> NYSETL.ECLRS.TestResult |> NYSETL.Repo.first()
      nil

      iex> NYSETL.ECLRS.TestResult |> NYSETL.Repo.first(order_by: [asc: :id])
      nil
  """
  @spec first(query :: Ecto.Queryable.t(), keyword()) :: any() | nil
  def first(query, opts \\ []) do
    order_by = Keyword.get(opts, :order_by, asc: :id)

    from(value in query)
    |> order_by(^order_by)
    |> limit(1)
    |> one
  end
end
