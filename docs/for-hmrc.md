# A note for HMRC

This page is for the Basic PAYE Tools team at HM Revenue & Customs.

## Summary

- Since recent macOS updates, the Basic PAYE Tools user interface does not open
  for some users (your
  [service availability and issues page](https://www.gov.uk/government/publications/basic-paye-tools-service-availability-and-issues/basic-paye-service-availability-and-issues)
  describes the Terminal workaround).
- **PAYE Launcher** is a small open-source macOS app that does that workaround
  for the user. It starts the server of the installed Basic PAYE Tools with
  the same commands as your user interface (`startdb`, `updatecheck`,
  `runserver`, `autobackup`) and shows the pages in a native window. It keeps
  your outstanding-submissions warning at exit.
- It contains **no HMRC code or material**. Users install Basic PAYE Tools from
  GOV.UK as normal, and their data stays in `~/HMRC/payetools-rti`.

## Apple Silicon without Rosetta

Your server bundle is x86_64 and needs Rosetta 2 on Apple Silicon. Your page
notes that Apple will end support for Intel apps on Apple Silicon from autumn 2027.

PAYE Launcher includes a universal (arm64 and x86_64) build of the open-source
runtime that your server uses (Python 2.7.16 and the same versions of 4Suite-XML, Pillow,
lxml and scandir). Your server code is Python bytecode, so it runs unchanged
on this runtime: the runtime loads it from the installed app at run time.

Each build compares both halves of this runtime with your own server
([testing.md](testing.md)): all reachable pages, static files, 1,620 net pay
estimator results over two tax years, IRmark generation and backups. All are
identical. A full employer and submission flow is not tested yet. It could be
tested against your test service with your agreement.

This could help you to support Apple Silicon Macs after Rosetta, without a
change to your server code.

## Use of this work

The source code is under the GNU GPL version 3, and the copyright owner is
open to other arrangements with HMRC, for example a different licence, a
transfer of the code, or help to bring the approach into your own build.
Please contact the maintainer through the GitHub profile
[github.com/nrbrook](https://github.com/nrbrook) or open an issue in this repository.

PAYE Launcher is not connected with or endorsed by HMRC. It uses the names
"HMRC" and "Basic PAYE Tools" only to say what it works with. If HMRC has any
concern about this project, please open an issue, and it will be dealt with
promptly.
