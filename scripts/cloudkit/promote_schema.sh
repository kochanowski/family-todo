#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCHEMA_JSON="${1:-$REPO_ROOT/cloudkit/schema/housepulse-schema.json}"
DRY_RUN="${DRY_RUN:-false}"
TEAM_ID="${TEAM_ID:-}"
CONTAINER_ID="${CONTAINER_ID:-iCloud.com.kochanowski.housepulse}"
TOKEN="${CLOUDKIT_MANAGEMENT_TOKEN:-}"
REQUIRED_SYSTEM_TYPES="${REQUIRED_SYSTEM_TYPES:-cloudkit.share}"

run_export() {
  local environment="$1"
  local output_file="$2"
  local log_file="$3"

  if [[ -n "$TOKEN" ]]; then
    if xcrun cktool export-schema \
      --team-id "$TEAM_ID" \
      --container-id "$CONTAINER_ID" \
      --environment "$environment" \
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
    --environment "$environment" \
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
prod_log_file="$tmp_dir/cktool-production-schema-check.log"
dev_ckdb_file="$tmp_dir/development-schema.ckdb"
dev_log_file="$tmp_dir/cktool-development-schema-check.log"

mkdir -p "$REPO_ROOT/cloudkit/artifacts"

echo "CloudKitSchema: checking production schema for container=$CONTAINER_ID"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "CloudKitSchema: DRY_RUN=true, skipping production schema export check."
  exit 0
fi

run_export production "$prod_ckdb_file" "$prod_log_file"
run_export development "$dev_ckdb_file" "$dev_log_file"

expected_types_file="$tmp_dir/expected-types.txt"
actual_types_file="$tmp_dir/actual-types.txt"
actual_dev_types_file="$tmp_dir/actual-development-types.txt"
required_types_file="$tmp_dir/required-types.txt"

jq -r '.recordTypes[].name' "$SCHEMA_JSON" | sort -u > "$expected_types_file"
awk '/^[[:space:]]*RECORD TYPE[[:space:]]+/ {print $3}' "$prod_ckdb_file" | sort -u > "$actual_types_file"
awk '/^[[:space:]]*RECORD TYPE[[:space:]]+/ {print $3}' "$dev_ckdb_file" | sort -u > "$actual_dev_types_file"
{
  cat "$expected_types_file"
  tr ',' '\n' <<<"$REQUIRED_SYSTEM_TYPES" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d'
} | sort -u > "$required_types_file"

missing_types="$(comm -23 "$required_types_file" "$actual_types_file" || true)"

cp "$prod_ckdb_file" "$REPO_ROOT/cloudkit/artifacts/production-schema-export.ckdb"
cp "$dev_ckdb_file" "$REPO_ROOT/cloudkit/artifacts/development-schema-export.ckdb"
if [[ -f "$prod_log_file" ]]; then
  cp "$prod_log_file" "$REPO_ROOT/cloudkit/artifacts/cktool-production-schema-check.log"
fi
if [[ -f "$dev_log_file" ]]; then
  cp "$dev_log_file" "$REPO_ROOT/cloudkit/artifacts/cktool-development-schema-check.log"
fi

if [[ -n "$missing_types" ]]; then
  echo "CloudKitSchema: production schema is missing required record type(s):" >&2
  echo "$missing_types" | sed 's/^/ - /' >&2

  while IFS= read -r missing_type; do
    [[ -z "$missing_type" ]] && continue
    if grep -Fxq "$missing_type" "$actual_dev_types_file"; then
      echo "CloudKitSchema: '$missing_type' exists in Development but not Production." >&2
      echo "CloudKitSchema: Deploy pending schema changes Development -> Production in CloudKit Console." >&2
    else
      echo "CloudKitSchema: '$missing_type' is missing in Development too." >&2
      if [[ "$missing_type" == "cloudkit.share" ]]; then
        echo "CloudKitSchema: Create at least one CKShare in Development first, then deploy schema to Production." >&2
      fi
    fi
  done <<<"$missing_types"
  exit 1
fi

echo "CloudKitSchema: production schema contains all required record types (including system types: $REQUIRED_SYSTEM_TYPES)."
