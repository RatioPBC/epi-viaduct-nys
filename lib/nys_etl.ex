defmodule NYSETL do
  @moduledoc """
  NYSETL keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  Defines an Ecto.Schema module.

  ## Examples

      defmodule NYSETL.MySchema do
        use NYSETL, :schema

        schema "my_schemas" do
          field :tid, :string
        end
      end
  """
  def schema do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
