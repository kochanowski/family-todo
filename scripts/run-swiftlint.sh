#!/usr/bin/env bash

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint not found, skipping"
  exit 0
fi

output=$(swiftlint lint --quiet --force-exclude 2>&1)
status=$?

if [ "$status" -eq 0 ]; then
  exit 0
fi

if [ "$status" -eq 132 ] || printf '%s' "$output" | grep -q "libsourcekitdInProc"; then
  printf '%s\n' "$output"
  echo "swiftlint failed to load SourceKit, skipping"
  exit 0
fi

printf '%s\n' "$output" >&2
exit "$status"
