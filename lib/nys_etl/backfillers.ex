defmodule NYSETL.Backfillers do
  alias NYSETL.Backfillers

  def backfill_abouts_checksums(), do: Backfillers.AboutsChecksums.backfill_all()
  def backfill_files_eclrs_version(), do: Backfillers.FilesECLRSVersion.backfill_all()
end
