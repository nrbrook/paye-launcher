# How PAYE Launcher works

## The problem

HMRC Basic PAYE Tools for macOS has two parts:

1. **The user interface** (`Basic PAYE Tools.app`): a Qt WebEngine window.
   After some macOS updates, this part does not open.
2. **The server** (`Contents/Helpers/rti.app`): a Django web application,
   frozen with py2app (Python 2.7.16). It holds all the payroll logic, the
   database code and the RTI submission code, and serves the pages at
   `http://127.0.0.1:46729/`.

The server still works. HMRC's workaround on GOV.UK starts it in Terminal
(`./rti runserver 46729`) and opens the pages in Safari.

## What PAYE Launcher does

PAYE Launcher replaces only the user interface (part 1). It contains no HMRC
code. At each start it:

1. Finds the newest installed Basic PAYE Tools (bundle identifier
   `uk.gov.hmrc.bptrti`), so HMRC updates are used automatically.
2. Reads the port from `~/HMRC/payetools-rti/bptshell-settings.ini` (default 46729).
3. Runs the same server commands as HMRC's user interface does
   (found from the strings in HMRC's app and from the server's command list):
   - `rti startdb`: makes or migrates the database,
   - `rti updatecheck`: checks GOV.UK for a new version,
   - `rti runserver <port>`: starts the web server.
4. Shows `http://127.0.0.1:<port>/` in a WebKit window. Links to other sites
   open in the default browser. PDFs go to Downloads. `window.print()` opens
   the macOS print panel.
5. At quit, asks the server `system/hasOutstandingSubmissions` (and the PCT
   version) and shows HMRC's warning if data is not sent. It then stops the
   server and runs `rti autobackup`, as HMRC's user interface does.

The user's data stays in `~/HMRC/payetools-rti`, the folder that the HMRC
server always uses. PAYE Launcher never writes to the HMRC app.

## The two runtimes

On an Intel Mac, PAYE Launcher runs HMRC's own `rti` executable.

On an Apple Silicon Mac, HMRC's `rti` is an Intel program that needs Rosetta 2.
Apple plans to end Rosetta support for most Intel apps, so PAYE Launcher
includes a **native runtime** and uses it by default:

- **Python 2.7.16**, built for arm64 with UCS-2 strings (the same as HMRC's
  build), with the Apple Silicon patches from pyenv.
- Native builds of the **open-source** packages that have C code, in the same
  versions as HMRC's app: 4Suite-XML 1.0.2, Pillow 6.2.2, lxml 4.5.2 and
  scandir 1.10.0.
- OpenSSL, SQLite and libjpeg-turbo, built from pinned sources and linked
  statically. libxml2, libxslt, zlib and libffi come from macOS (HMRC's lxml
  also uses the macOS libxml2 and libxslt).

All the HMRC code in the server is Python bytecode (`.pyc`), which does not
depend on the processor type. `runtime/bpt_native_boot.py` does what the
py2app start-up files of HMRC's app do (environment variables, `sys.frozen`,
`sys.path`, working folder). It puts the native packages before HMRC's Intel
copies, and then runs HMRC's `manage.py`. The HMRC files are loaded unchanged
from the installed app at run time, and nothing is written to the HMRC app.

The user can switch to HMRC's own server with **PAYE Launcher > Use Apple
Silicon Runtime**. If the native runtime cannot start, PAYE Launcher offers
HMRC's own server.

## Why the runtime contains no HMRC code

The runtime is built only from public open-source sources (see
`runtime/sources.sh`). The download does not contain, convert or change any
HMRC file. Each user runs the copy of Basic PAYE Tools that they installed
from GOV.UK. See [testing.md](testing.md) for the checks that the native
runtime gives the same results as HMRC's own server.

## Code layout

- `Sources/PAYELauncherCore`: logic without UI, covered by unit tests.
  `BPTInstallation` (find the app), `ShellSettings` (port), `Runtime` (choose
  the runtime, build commands), `BPTServer` (start, wait, stop, backup),
  `ProcessRunner`, `LocalServer` (link rules, outstanding submissions),
  `Logger`, `Preferences`.
- `Sources/PAYELauncher`: the AppKit app. `AppDelegate` (start-up and quit),
  `BrowserWindowController` (web view, downloads, dialogs, printing),
  `MainMenu`, `Alerts`.
- `runtime/`: the native runtime build and the comparison tests.
