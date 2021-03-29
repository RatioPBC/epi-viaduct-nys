defmodule NYSETL.Extra.ScrubberTest do
  use NYSETL.SimpleCase, async: true

  alias NYSETL.Extra.Scrubber

  doctest Scrubber

  describe "scrub_file" do
    test "it scrubs a v1 fixture file" do
      # The thing we are testing is based on randomness.  In order to test it, we need to control the
      # random seed just like we do in all the doctests.  But seeds are local to processes, and
      # `scrub_file` uses Flow to parallelise processing, which means that we cannot control the seed
      # from inside the test.  The workaround is to run the test data through `scrub_row` synchronously first,
      # thereby populating the shared conversion memory in ETS.  Once we have that, we can test `scrub_file`'s
      # parallel processing since the scrubbing as such will be predictable.

      # Step 1: Populate scrubbing cache.
      ets = :ets.new(:scrubber_test, [:public])
      :rand.seed(:exsss, {101, 102, 103})
      "test/fixtures/eclrs/new_records.txt" |> File.stream!() |> Enum.each(&Scrubber.scrub_row({:v1, &1}, ets))

      # Step 2: Test `scrub_file` in predictable mode.
      output_path = Briefly.create!()
      {:ok, 3} = Scrubber.scrub_file("test/fixtures/eclrs/new_records.txt", output_path, ets)
      assert File.read!(output_path) == File.read!("test/fixtures/eclrs/new_records_scrubbed.txt")
    end

    test "it doesn't require an ETS database to be provided" do
      output_path = Briefly.create!()
      assert {:ok, 3} = Scrubber.scrub_file("test/fixtures/eclrs/new_records.txt", output_path)
    end
  end
end
