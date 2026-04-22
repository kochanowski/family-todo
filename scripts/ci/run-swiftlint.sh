#!/usr/bin/env bash

set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found, cannot run swiftlint container" >&2
  exit 1
fi

# pre-commit can pass many file types in some flows; only keep Swift files.
swift_files=()
for file in "$@"; do
  if [[ "$file" == *.swift ]]; then
    swift_files+=("$file")
  fi
done

# Nothing to lint in this invocation.
if [ "${#swift_files[@]}" -eq 0 ]; then
  exit 0
fi

docker run --rm \
  -v "$PWD":"$PWD" \
  -w "$PWD" \
  ghcr.io/realm/swiftlint:latest \
  lint --quiet --force-exclude "${swift_files[@]}"
