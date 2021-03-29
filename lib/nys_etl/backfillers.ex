defmodule NYSETL.Backfillers do
  alias NYSETL.Backfillers

  def backfill_files_eclrs_version(), do: Backfillers.FilesECLRSVersion.backfill_all()
end
