# Integration Testing

Integration testing in this context means processing test results locally in the development environment, and uploading any created / updated index cases and test results to Dimagi.

By default, the dev environment does not run the `NYSETL.ViaductSupervisor` and so does not run any engines. This gives you more control over the process - you can run each stage of the workflow manually.

The basic process for integration testing is:

1. (Optionally) import any desired index cases from CommCare.
2. Create an ECLRS file with necessary test data.
3. Extract the file with `NYSETL.Engines.E1.ECLRSFileExtractor`.
4. Process test results with `NYSETL.Engines.E2.TestResultProcessor`.
5. Load index cases to CommCare with `NYSETL.Engines.E4.CommcareCaseLoader`.

You can run the entire process automatically with `NYSETL.ViaductSupervisor.start_link/1`. The only thing you'll need to manually do is extract the ECLRS file (because there will be no SQS event for `NYSETL.Engines.E1.SQSTask` to read).

## County setup

Make sure there's a county record that has the ID corresponding to the county code you use (e.g. id=800 tid="ny-integrations-cdcms").

## Partial automation

It is probably easiest to manually import index cases from CommCare, extract an ECLRS file, and then let Viaduct handle the rest. This means running Oban:

```elixir
Oban.start_link(Application.get_env(:nys_etl, Oban))
NYSETL.Engines.E2.TestResultProducer.start_link()
```

## Import index cases from CommCare

To manually import cases one at a time:

```elixir
# Get a reference to the county struct
county =
  NYSETL.Commcare.County.participating_counties()
  |> Enum.find(& &1.domain == "ny-integrations-cdcms")

# Fetch the case
{:ok, cc} = NYSETL.Commcare.Api.get_case(
  commcare_case_id: "96204059-54b2-401d-b68e-db92030fda02",
  county_domain: "ny-integrations-cdcms"
)

# Import the case data
NYSETL.Engines.E5.Processor.process(case: cc, county: county)
```

## Create an ECLRS file

Copy a file from `test/fixtures/eclrs` and edit it. Assign each test result:

- the correct first name, last name, and date of birth (if it is to correspond to imported people / cases)
- a unique accession number
- a unique patient key
- a county code that maps to a domain (e.g. 800 for "ny-integrations-cdcms")

## Extract the file

Using `NYSETL.Engines.E1.ECLRSFileExtractor.extract!/1` (with Oban running):

```elixir
NYSETL.Engines.E1.ECLRSFileExtractor.extract!("path/to/file.txt")
```

Using `NYSETL.Engines.E1.ECLRSFileExtractor.extract/1` (without Oban running):

```elixir
NYSETL.Engines.E1.ECLRSFileExtractor.extract("path/to/file.txt")
NYSETL.Engines.E1.ECLRSFileExtractor.wait()
NYSETL.Engines.E1.ECLRSFileExtractor.stop()
```


## Process test result

Using `NYSETL.Engines.E2.TestResultProcessor.perform/1`:

```elixir
NYSETL.Engines.E2.TestResultProcessor.process(%{args: %{"test_result_id" => 1}})
```

## Load index case to CommCare

Using `NYSETL.Engines.E4.CommcareCaseLoader.perform/1`:

```elixir
county =
  NYSETL.Commcare.County.participating_counties()
  |> Enum.find(& &1.domain == "ny-integrations-cdcms")

NYSETL.Engines.E4.CommcareCaseLoader.perform(%{
  args: %{
    "case_id" => "96204059-54b2-401d-b68e-db92030fda02",
    "county_id" => county.fips
  }
})
```
