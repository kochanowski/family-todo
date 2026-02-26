#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCHEMA_JSON="${1:-$REPO_ROOT/cloudkit/schema/housepulse-schema.json}"
DRY_RUN="${DRY_RUN:-false}"
TEAM_ID="${TEAM_ID:-}"
CONTAINER_ID="${CONTAINER_ID:-iCloud.com.kochanowski.housepulse}"
TOKEN="${CLOUDKIT_MANAGEMENT_TOKEN:-}"

run_export() {
  local output_file="$1"
  local log_file="$2"

  if [[ -n "$TOKEN" ]]; then
    if xcrun cktool export-schema \
      --team-id "$TEAM_ID" \
      --container-id "$CONTAINER_ID" \
      --environment production \
      --output-file "$output_file" \
      --token "$TOKEN" \
      2>&1 | tee "$log_file"; then
      return 0
    fi

    if grep -qi "unknown option.*--token" "$log_file"; then
      echo "CloudKitSchema: cktool does not support --token for export-schema; retrying without --token." | tee -a "$log_file"
    else
      return 1
    fi
  fi

  xcrun cktool export-schema \
    --team-id "$TEAM_ID" \
    --container-id "$CONTAINER_ID" \
    --environment production \
    --output-file "$output_file" \
    2>&1 | tee "$log_file"
}

if [[ -z "$TEAM_ID" ]]; then
  echo "CloudKitSchema: TEAM_ID is required." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "CloudKitSchema: jq is required." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "CloudKitSchema: xcrun is required (macOS runner with Xcode)." >&2
  exit 1
fi

"$SCRIPT_DIR/validate_schema.sh" "$SCHEMA_JSON"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
prod_ckdb_file="$tmp_dir/production-schema.ckdb"
log_file="$tmp_dir/cktool-production-schema-check.log"

mkdir -p "$REPO_ROOT/cloudkit/artifacts"

echo "CloudKitSchema: checking production schema for container=$CONTAINER_ID"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "CloudKitSchema: DRY_RUN=true, skipping production schema export check."
  exit 0
fi

run_export "$prod_ckdb_file" "$log_file"

expected_types_file="$tmp_dir/expected-types.txt"
actual_types_file="$tmp_dir/actual-types.txt"

jq -r '.recordTypes[].name' "$SCHEMA_JSON" | sort -u > "$expected_types_file"
awk '/^[[:space:]]*RECORD TYPE[[:space:]]+/ {print $3}' "$prod_ckdb_file" | sort -u > "$actual_types_file"

missing_types="$(comm -23 "$expected_types_file" "$actual_types_file" || true)"

cp "$prod_ckdb_file" "$REPO_ROOT/cloudkit/artifacts/production-schema-export.ckdb"
if [[ -f "$log_file" ]]; then
  cp "$log_file" "$REPO_ROOT/cloudkit/artifacts/cktool-production-schema-check.log"
fi

if [[ -n "$missing_types" ]]; then
  echo "CloudKitSchema: production schema is missing required record type(s):" >&2
  echo "$missing_types" | sed 's/^/ - /' >&2
  echo "CloudKitSchema: CloudKit Management API does not support direct import to production with cktool." >&2
  echo "CloudKitSchema: Required manual step in CloudKit Console (Production): click 'Deploy Schema Changes...' and publish pending changes." >&2
  exit 1
fi

echo "CloudKitSchema: production schema contains all required record types."
