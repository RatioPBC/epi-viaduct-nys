# Performance statistics

These stats are generated using data from 2021-10-19 to 2021-11-29 and encompass ~300,000 unique test results. We chose 2021-10-19 as the cutoff, because on 2021-10-18 we replaced a Broadway implementation with Oban to dramatically speed up test result processing.

Viaduct processes ECLRS files much faster than ECLRS can send them. ECLRS sends files every 30 minutes, and Viaduct processes an ECLRS file in ~15 seconds.

`NYSETL.Engines.E4.CommcareCaseLoader` and `NYSETL.Commcare.CaseImporter` make API calls to CommCare, and so are subject to network connectivity and CommCare API's responsiveness.

## Processing ECLRS files

ECLRS exports the previous 2 weeks' worth of positive test results.

`NYSETL.Engines.E1.ECLRSFileExtractor.extract!/1` and `NYSETL.Engines.E1.Processor.process/1` work together to process an individual file, saving any unique test result rows to the database.

**Average time to parse**: 14.6 seconds (2.3 seconds standard deviation)

```sql
select
  avg(how_long),
  stddev(how_long)
from
  (
    select
      extract(
        epoch
        from
          processing_completed_at - processing_started_at
      ) as how_long
    from
      files
    where
      processing_completed_at is not null
      and inserted_at >= '2021-10-19'
  ) as how_long_query;
```

## Preparing test results for CommCare

`NYSETL.Engines.E2.Processor.process/2` processes an individual test result, and creates or updates index cases and lab results within the Viaduct database.

**Average time to process**: 3.9 seconds (3.7 seconds standard deviation)

```sql
select
  avg(how_long),
  stddev(how_long)
from
  (
    select
      extract(
        epoch
        from
          completed_at - inserted_at
      ) as how_long
    from
      oban_jobs
    where
      worker = 'NYSETL.Engines.E2.TestResultProcessor'
      and inserted_at >= '2021-10-19'
      and completed_at is not null
  ) as how_long_query;
```

## Uploading to CommCare


**Average time to upload**: 3.5 seconds (109 seconds standard deviation)

```sql
select
  avg(how_long),
  stddev(how_long)
from
  (
    select
      extract(
        epoch
        from
          completed_at - inserted_at
      ) as how_long,
      attempt
    from
      oban_jobs
    where
      worker = 'NYSETL.Engines.E4.CommcareCaseLoader'
      and inserted_at >= '2021-10-19'
      and completed_at is not null
  ) as how_long_query;
```

## Importing from CommCare

CommCare uses its [case forwarder](https://confluence.dimagi.com/pages/viewpage.action?pageId=12224128) to send updates to Viaduct.

`NYSETL.Commcare.CaseImporter.perform/1` typically takes less than a second to complete.
