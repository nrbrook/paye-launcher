SHELL := /bin/bash
RUNTIME ?= $(HOME)/Library/Caches/PAYELauncher/runtime-build/runtime
SHELL_SCRIPTS := $(wildcard scripts/*.sh runtime/*.sh runtime/tests/*.sh)

.PHONY: help build test lint format runtime compare app clean

help:
	@echo "make build    - build the app (debug)"
	@echo "make test     - run the unit tests"
	@echo "make lint     - run SwiftLint, Ruff and ShellCheck"
	@echo "make runtime  - build the native Apple Silicon runtime"
	@echo "make compare  - compare the native runtime with HMRC's server (needs Basic PAYE Tools)"
	@echo "make app      - build dist/PAYE Launcher.app and the DMG (ad-hoc signed)"

build:
	swift build

test:
	swift test

lint:
	swiftlint lint --strict --quiet
	ruff check .
	ruff format --check .
	@if command -v shellcheck > /dev/null; then shellcheck -x $(SHELL_SCRIPTS); else echo "shellcheck not installed (brew install shellcheck); skipped"; fi
	@if command -v actionlint > /dev/null; then actionlint; else echo "actionlint not installed (brew install actionlint); skipped"; fi

format:
	swiftlint lint --fix --quiet
	ruff format .

runtime:
	runtime/build_runtime.sh

compare:
	runtime/tests/run_comparison.sh "$(RUNTIME)"

app:
	scripts/package_app.sh --runtime "$(RUNTIME)"

clean:
	rm -rf .build dist
