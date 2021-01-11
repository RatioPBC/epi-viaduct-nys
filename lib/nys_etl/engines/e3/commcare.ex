defmodule NYSETL.Engines.E3.Commcare do
  @moduledoc """
  It is not entirely clear that this module is useful and necessary.
  """

  alias NYSETL.Engines.E3

  def start_link() do
    {:ok, _county_list, _} = NYSETL.Commcare.Api.get_county_list()
    E3.Supervisor.start_link()
  end

  def stop() do
    E3.Supervisor.stop()
  end
end
