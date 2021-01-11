# Epi Viaduct for New York State

_Epi Viaduct_ is a data pipeline system that transfers Covid-19 lab result data from a jurisdiction's Electronic
Lab Result system to a case management system that coordinates and supports the work of case investigators and
contact tracers.  _Epi Viaduct for New York State_ is specifically built to transfer data from
[ECLRS](https://www.health.ny.gov/professionals/reportable_diseases/eclrs/) to NY-CDCMS, a contact tracing system
built on [CommCare](https://dimagi.com/commcare/) from [Dimagi](https://dimagi.com/).

The development of _Epi Viaduct_ in NY and other jurisdictions is sponsored by [Resolve to Save Lives, an
initiative of Vital Strategies](https://resolvetosavelives.org/).

## Usage

The source code is published here to inspire others to do similar work, but it is not expected that the code be
reusable in any other settings than those for which it was written.  Anyone interested in studying the code should
be able to download it and run the test suite.  A [Technical Introduction](technical_introduction.md) is available
for those wanting to become more familiar with the code.

The software is being actively developed on MacOS and Linux, but it's probably not too hard to get it running under
Windows, especially using WSL2.

### Getting started

After cloning this repo, run `bin/dev/doctor`.  If it finds a problem, it will *suggest* a remedy, which it will
put in the clipboard.  If you think the remedy will work well on your computer, paste it into your terminal.  You
can also try a different remedy—`doctor` is not omnipotent.  Then run `doctor` over and over until it succeeds.
(Note: `doctor` may not work well on Windows.)

Once `doctor` has succeeded, you should be able to run the test suite: `mix test`.

The application currently depends on [Oban Pro](https://getoban.pro/), which is a commercial plugin to the queue
manager [Oban](https://hexdocs.pm/oban), and a (relatively cheap) license is required to complete the installation
and run the test suite.  We are working on making Oban Pro optional in the future.

## Contributing

Viaduct is open-source, meaning that you can make as many copies of it as you want and do whatever you want with
those copies, without limitation. But Viaduct is not open-contribution. It was built for one user, and it's being
maintained for that user only.  Also, in order to keep Viaduct in the public domain and ensure that the code does
not become contaminated with proprietary or licensed content, the project does not accept patches from unknown
persons.

## Copyright and license

Copyright © 2020 Geometer, LLC, and Resolve to Save Lives. The code is made available under the MIT license.  See
also [License](LICENSE.md).
