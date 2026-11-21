# PAYE Launcher

**Opens HMRC Basic PAYE Tools on a Mac when the HMRC app does not open.**

After some macOS updates, the Basic PAYE Tools app from HMRC does not open
(see HMRC's
[service availability and issues page](https://www.gov.uk/government/publications/basic-paye-tools-service-availability-and-issues/basic-paye-service-availability-and-issues)).
HMRC's workaround is to type commands into Terminal each time you use it.
PAYE Launcher does those steps for you and shows Basic PAYE Tools in its own
window, like a normal app.

> PAYE Launcher is free, open-source software. It is **not** made by, connected
> with or endorsed by HMRC. It contains no HMRC software: it runs the copy of
> Basic PAYE Tools that you installed from GOV.UK.

## Install

1. **Install Basic PAYE Tools from GOV.UK** if you do not have it:
   [www.gov.uk/basic-paye-tools](https://www.gov.uk/basic-paye-tools).
   Keep it installed. PAYE Launcher needs it.
2. **Download PAYE Launcher**: open the
   [latest release](https://github.com/nrbrook/paye-launcher/releases/latest)
   and click **PAYE-Launcher-…dmg** under *Assets*.
3. **Open the downloaded file** and drag **PAYE Launcher** to the
   **Applications** folder.
4. **Open PAYE Launcher** from the Applications folder. The first time, macOS
   asks if you are sure that you want to open an app from the internet.
   Click **Open**.

Basic PAYE Tools then opens in the PAYE Launcher window. You can keep
PAYE Launcher in the Dock: right-click its icon and choose
**Options > Keep in Dock**.

## Use

- Use Basic PAYE Tools as normal. Links to GOV.UK open in your web browser.
- **Printable forms** (PDF) are saved in your Downloads folder and open in
  Preview.
- **To print a page**, choose **File > Print**. To save it as a PDF, choose
  **PDF > Save as PDF** in the print window.
- **To close**, quit PAYE Launcher (**PAYE Launcher > Quit PAYE Launcher**, or
  ⌘Q). As with HMRC's app, you are warned if there are submissions that are not
  sent, and an automatic backup is made.

## Your data

PAYE Launcher does not move or change your data. Basic PAYE Tools keeps it
where it always does: the **HMRC** folder in your home folder
(`~/HMRC/payetools-rti`), with backups in its `backups` folder. To see it,
choose **PAYE Launcher > Show Data Folder**.

PAYE Launcher sends nothing anywhere. Basic PAYE Tools itself connects to
HMRC when you send submissions and to GOV.UK to check for updates, as usual.

## Questions

**Is this from HMRC?**
No. It is an independent open-source project. HMRC does not support it.

**Is it safe?**
The full source code is public in this repository, every release is built
automatically from it on GitHub, and the download is signed and notarised by
Apple. You can check that a download came from this repository: see
[Check a download](#check-a-download).

**Does it change Basic PAYE Tools or my payroll calculations?**
No. It does not change any HMRC file. The calculations, submissions and
database are HMRC's own code.

**What is "Use Apple Silicon Runtime"?**
HMRC's server program is made for Intel Macs. On Apple Silicon Macs (M1 and
later) it needs Apple's Rosetta translator, which Apple will remove from future
versions of macOS. PAYE Launcher includes a native Apple Silicon version of the
open-source parts (Python and its libraries). It runs HMRC's own, unchanged
code without Rosetta. This is on by default. Each release is tested to make the
same results as HMRC's own server (see [docs/testing.md](docs/testing.md)).
To use HMRC's own server instead, turn off **PAYE Launcher > Use Apple
Silicon Runtime**. On Intel Macs, PAYE Launcher always uses HMRC's own server.

**What if HMRC fixes their app?**
Then you can use either. PAYE Launcher always uses the installed version of
Basic PAYE Tools, so HMRC updates work as normal: install them from GOV.UK.

**Which Macs?**
macOS 13 Ventura or later, Apple Silicon or Intel.

## Problems

- **"Basic PAYE Tools is not installed"**: install it from GOV.UK (step 1).
- **"Basic PAYE Tools is already running"**: another copy is open, for example
  one that you started in Terminal with HMRC's workaround. Close it, then click
  **Try Again**.
- **It does not start**: choose **Use HMRC's Server** in the message, or turn
  off **Use Apple Silicon Runtime**. The log file (**PAYE Launcher > Show Log
  File**) has the details.
- To report a problem, use **Help > Report a Problem with PAYE Launcher**.
  **Do not post payroll or personal data.**

For questions about payroll, calculations or submissions, contact HMRC.

## Check a download

Each release lists the SHA-256 of the DMG, and has a build provenance
attestation from GitHub. With the [GitHub CLI](https://cli.github.com):

```bash
shasum -a 256 PAYE-Launcher-*.dmg
gh attestation verify PAYE-Launcher-*.dmg -R nrbrook/paye-launcher
```

## For developers

| Folder | Content |
|---|---|
| `Sources/PAYELauncherCore` | Logic: find Basic PAYE Tools, build server commands, run processes, link rules |
| `Sources/PAYELauncher` | The macOS app (AppKit and WebKit) |
| `Tests/` | Unit tests (Swift Testing) |
| `runtime/` | Build of the native Apple Silicon runtime, and its comparison tests |
| `scripts/` | Version, packaging, signing, notarisation |
| `.github/workflows/` | CI for pull requests, and the release workflow |

```bash
make test       # unit tests
make lint       # SwiftLint, Ruff, ShellCheck, actionlint
make runtime    # build the native runtime (about 3 minutes)
make compare    # compare it with HMRC's server (needs Basic PAYE Tools installed)
make app        # dist/PAYE Launcher.app and DMG (ad-hoc signed)
```

Read [docs/how-it-works.md](docs/how-it-works.md),
[docs/testing.md](docs/testing.md) and [docs/releasing.md](docs/releasing.md).
Contributions are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md).

Versions are dates: `2026.11.21`, then `2026.11.21.2` for a second release
on the same day.

## License

Copyright © 2026 Nick Brook. PAYE Launcher is free software under the
[GNU General Public License version 3](LICENSE). The download also contains
open-source components under their own licenses: see
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

Basic PAYE Tools is Crown copyright software of HM Revenue & Customs and is not
part of this project. "HMRC" and "Basic PAYE Tools" are used only to say what
PAYE Launcher works with.
