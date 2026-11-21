# Contributing

Thank you for your help. Bug reports, tests on different Macs and pull
requests are all welcome.

## Rules

1. **No HMRC material.** Do not add HMRC code, files, data, logos or other
   material, also not in tests or examples. Tests download Basic PAYE Tools
   from GOV.UK at run time.
2. **No personal or payroll data**, anywhere: issues, logs, tests or screenshots.
3. Keep the app simple for non-technical users. Messages are in plain English.
4. `make lint` and `make test` must pass. If you change the runtime, run
   `make runtime compare` too.

## Contribution terms

PAYE Launcher is licensed under the GNU GPL version 3. The maintainer wants to
keep the option to offer it to HMRC under other terms (for example a licence
or a transfer of the code). Thus, by submitting a contribution you agree that:

- your contribution is your own work, or you have the right to submit it;
- it is licensed under the GNU GPL version 3; and
- you also grant Nick Brook a perpetual, worldwide, non-exclusive, royalty-free,
  irrevocable licence to use, change, sublicense and relicense your
  contribution under other terms, including commercial terms.

Add a `Signed-off-by:` line to your commits (`git commit -s`) to confirm this.

## Development

```bash
make build     # debug build
make test      # unit tests
make lint      # linters (install with: brew install swiftlint ruff shellcheck actionlint)
make runtime   # native runtime
make compare   # compare it with HMRC's server
make app       # app and DMG
```

See [docs/how-it-works.md](docs/how-it-works.md) for the design.
