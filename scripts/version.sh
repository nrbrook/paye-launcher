#!/bin/bash
# Prints the release version, based on the date (UTC): YYYY.MM.DD
# If a tag for that date exists, it adds a number: YYYY.MM.DD.2, YYYY.MM.DD.3, ...
#
# Usage: scripts/version.sh            -> 2026.11.21
#        scripts/version.sh --build    -> 2026112101 (CFBundleVersion: date and number)
set -euo pipefail

date_version="${VERSION_DATE:-$(date -u '+%Y.%m.%d')}"
version="$date_version"
number=1
if git rev-parse --git-dir > /dev/null 2>&1; then
  while git rev-parse -q --verify "refs/tags/v$version" > /dev/null; do
    number=$((number + 1))
    version="$date_version.$number"
  done
fi

if [ "${1:-}" = "--build" ]; then
  printf '%s%02d\n' "${date_version//./}" "$number"
else
  echo "$version"
fi
