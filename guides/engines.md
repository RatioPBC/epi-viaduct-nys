# Viaduct Engines

Viaduct is built for speed and asynchronous processing with clear separations of responsibilities. The code can be
divided into 5 [engines](https://en.wikipedia.org/wiki/Software_engine) that each perform their own work independent of
the others.  The engines are

* Engine 1: The *ECLRS extractor* that takes the ECLRS export files from S3, weeds out the lines Viaduct has seen
    before, and inserts all new lines into the database.
* Engine 2: The *ECLRS->CommCare Transformer* that discovers as-yet unprocessed lines from ECLRS,
    finds or creates a "person" (Viaduct's own, internal concept) and then creates or updates the records that will later
    be sent to CommCare: an "index case" and a "lab result".
* Engine 3: The *CommCare Enqueuer* that discovers index cases that haven't been synched to CommCare since their
    last change, and puts them on the Oban queue for controlled processing.
* Engine 4: The *CommCare Case Loader* that takes one index case at a time and posts it and its lab results to
    CommCare after figuring out which county's project space it belongs to - either the one that ECLRS said, or one
    to which it has been transferred within CommCare.
* Engine 5: The *CommCare Extractor* which runs constantly, synching down new and updated information about
    patients that we recognize.

The "independent" aspect bears elaborating: Rather than one engine passing work to the next one in the conceptual
pipeline, each engine looks for data (in the database, etc) that is ready to be processed by that engine.  Thus,
the API between the engines is not a callable API, but data at rest in a certain format.

In the following sections we are going to look at each of the engines in more detail.  The code for each engine
can be found in `lib/nys_etl/engines/e1` for engine 1, etc.

## E1: ECLRS extractor

`NYSETL.Engines.E1.*`: _A Broadway pipeline started on demand by a Task that listens for SQS notifications._

The NYS DOH delivers a 14-day export of positive Covid-19 test results to an [Amazon S3](https://aws.amazon.com/s3/) bucket roughly every 30 minutes. S3
notifies Viaduct (via [Amazon SNS](https://aws.amazon.com/sns/) and [Amazon SQS](https://aws.amazon.com/sqs/)) when a new file is received.  This notification is received by `NYSETL.Engines.E1.SQSListener`
in collaboration with `NYSETL.Engines.E1.SQSTask`, which then kick off `NYSETL.Engines.E1.ECLRSFileExtractor`, which in turn starts the
engine's `NYSETL.Engines.E1.Supervisor` and actively waits for it to finish before letting `NYSETL.Engines.E1.SQSTask` listen for the next
notification.

`NYSETL.Engines.E1.Supervisor` starts two children: `NYSETL.Engines.E1.State`, which keeps track of the main process's progress, and `NYSETL.Engines.E1.Broadway`
which orchestrates a two-step [Broadway
pipeline](https://samuelmullen.com/articles/understanding-elixirs-broadway/) to process all rows in the input file.
Rows are read from the ECLRS file by `NYSETL.Engines.E1.FileReader`, and then converted from plain strings
to `NYSETL.Engines.E1.Message`s which contain the raw row, its checksum, and a `Map` with the data, prepared for the database. These
messages are then processed by `NYSETL.Engines.E1.Processor` which stores them in the `test_results` table along with some
meta-data in the `abouts` table (if the information is new) or just updates the corresponding record in the
`abouts` table (if the ECLRS row has been seen before).

At the end of the import round, some summary statistics is stored in the `files` table.

Notes:

* The `files` table has a unique index on the file path to make sure we don't import the same file twice.  This
  worked well when the files were stored orderly on the server, but since we switched to on-the-fly downloading to
  a random tmp path, the uniquiness constraint is moot.

## E2: ECLRS->CommCare Transformer

`NYSETL.Engines.E2.*`: _A Broadway pipeline that runs continuously._

`NYSETL.Engines.E2.TestResultProducer` queries the database for `test_results` records that have no finished-state
`test_result_events` record and makes them available to the pipeline.  `NYSETL.Engines.E2.Processor.process/2` processes the records one by
one in parallel like so:

* Find a person in the `people` table that matches patient key, or exact combination of date of birth, last name and first name. If none found, create one.
* Look up index cases in the same county of the test result, creating a new one if necessary.
* For the index case(s) in the previous step, update lab result records with the "accession number" in the test result.  If an index case does not have a lab result with that accession number, create one.

Notes:

* "Update" means add-if-missing.  Viaduct never overwrites existing data.
* While idling, the producer polls the database every 5 seconds for unprocessed test result records.  While
  processing, it polls every 100 ms or when requested by Broadway.
* A single ECLRS row, which contains information about _one_ test result, may result in several lab result records
  being created if the "person" in Viaduct has more than one index case in the county of the test result.
* For historical reasons, Engine 2 borrows the `NYSETL.Engines.E1.Cache` library from Engine 1.
* First names are split on spaces, and the first part gets used. e.g. a first name of "Mary Ann" would match on "Mary".

## E3: CommCare Enqueuer

`NYSETL.Engines.E3.*`: _A Broadway pipeline that runs continuously._

`NYSETL.Engines.E3.IndexCaseProducer` queries the database for index cases that have not been enqueued since they were last
updated.  All such index cases are enqueued in Oban for processing by `NYSETL.Engines.E4.CommcareCaseLoader`.

Notes:

* While idling, the producer polls the database every 5 seconds for enqueueable index cases.  While processing, it
  polls every second or when requested by Broadway.

## E4: CommCare Case Loader

`NYSETL.Engines.E4.*`: _An Oban Worker that is retried up to 20 times over a number of days._

`NYSETL.Engines.E4.CommcareCaseLoader` creates or updates an index case with all its lab results to the county domain in CommCare
where it belongs.  Before posting, `NYSETL.Engines.E4.CaseTransferChain` is used to determine if the index case has been
transferred to another county domain within CommCare.  If so, `NYSETL.Engines.E4.CaseTransferChain` tries to find the index case in
the transfer destination county domain and update that one instead.

Notes:

* A single ECLRS row, which contains information about _one_ test result, may result in several lab result records
    being created if the "person" in Viaduct has more than one index case in the county of the test result.  The
    index cases, and thus the lab results, are enqueued separately and posted separately to CommCare.
* A transfer chain can be long and winding and might even be circular.  Sometimes it is not possible to find the
    final index case in the chain.  Sometimes it would be possible, but it's not sure that implementing a solution
    would be an overall gain: it might solve some case but make the whole system too complicated to reason about.
* If a final-destination index case cannot be found, it is always the case that the same lab result that Viaduct is
    trying to publish can also be found on another index case, often in the right county.  For that reason, broken
    transfer chains are rarely a problem.

## E5: CommCare Extractor

`NYSETL.Engines.E5.*`: _A Broadway pipeline that runs continuously._

`NYSETL.Engines.E5.Producer` wakes up every five minutes and polls CommCare for all changes to index cases since midnight.  It
works its way through the counties list (in reverse alphabetical order), downloading index cases and their lab
results. `NYSETL.Engines.E5.Processor` processes the cases according to the first rule that matches:

* An index case with this `case_id` exists in our DB:
    * Update the case with changes from CommCare, but ignore any new lab results.
* A person exists that can be matched by dob + last_name + first_name:
    * Create an index case linked to the person and lab results linked to the index case.
* If no matching case or person exists:
    * Create a person, index case, and lab result record(s).

Notes:

* We're polling for changes since midnight since that is what we thought the API allowed.  We've since found how
  to express a timestamp that would allow us to fetch changes since any time, and we should fix that at some point.
* The data we sync down is used when merging records in Engine 3.  It is not (yet) used to figure out transfer
  chains for Engine 4.
