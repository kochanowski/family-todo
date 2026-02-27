#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCHEMA_JSON="${1:-$REPO_ROOT/cloudkit/schema/housepulse-schema.json}"
DRY_RUN="${DRY_RUN:-false}"
TEAM_ID="${TEAM_ID:-}"
CONTAINER_ID="${CONTAINER_ID:-iCloud.com.kochanowski.housepulse}"
TOKEN="${CLOUDKIT_MANAGEMENT_TOKEN:-}"

render_ckdb() {
  local input_json="$1"
  local output_ckdb="$2"

  jq -r '
    def to_type:
      if . == "String" then "STRING"
      elif . == "Int64" then "INT64"
      elif . == "Date" then "TIMESTAMP"
      elif . == "Reference" then "REFERENCE"
      elif . == "ReferenceList" then "LIST<REFERENCE>"
      else error("Unsupported type: \(.)")
      end;

    "DEFINE SCHEMA\n"
    + (
      .recordTypes
      | map(
          "RECORD TYPE \(.name) (\n"
          + (
              .fields
              | map(
                  "  \"\(.name)\" "
                  + (.type | to_type)
                  + (if .queryable then " QUERYABLE" else "" end)
                  + (if .sortable then " SORTABLE" else "" end)
                )
              | join(",\n")
            )
          + "\n);"
        )
      | join("\n\n")
    )
  ' "$input_json" > "$output_ckdb"
}

run_import() {
  local ckdb_file="$1"
  local log_file="$2"

  if [[ -n "$TOKEN" ]]; then
    if xcrun cktool import-schema \
      --team-id "$TEAM_ID" \
      --container-id "$CONTAINER_ID" \
      --environment development \
      --file "$ckdb_file" \
      --token "$TOKEN" \
      2>&1 | tee "$log_file"; then
      return 0
    fi

    if grep -qi "unknown option.*--token" "$log_file"; then
      echo "CloudKitSchema: cktool does not support --token flag in this runtime; retrying without --token." | tee -a "$log_file"
    else
      return 1
    fi
  fi

  xcrun cktool import-schema \
    --team-id "$TEAM_ID" \
    --container-id "$CONTAINER_ID" \
    --environment development \
    --file "$ckdb_file" \
    2>&1 | tee "$log_file"
}

run_export_development() {
  local output_file="$1"
  local log_file="$2"

  if [[ -n "$TOKEN" ]]; then
    if xcrun cktool export-schema \
      --team-id "$TEAM_ID" \
      --container-id "$CONTAINER_ID" \
      --environment development \
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
    --environment development \
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
ckdb_file="$tmp_dir/schema.ckdb"
log_file="$tmp_dir/cktool-apply-development.log"
dev_export_ckdb_file="$tmp_dir/development-schema-export.ckdb"
dev_export_log_file="$tmp_dir/cktool-development-schema-export.log"

render_ckdb "$SCHEMA_JSON" "$ckdb_file"

echo "CloudKitSchema: generated ckdb schema at $ckdb_file"

echo "CloudKitSchema: applying schema to development environment for container=$CONTAINER_ID"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "CloudKitSchema: DRY_RUN=true, skipping import-schema command."
else
  set +e
  run_import "$ckdb_file" "$log_file"
  import_status=$?
  set -e

  if [[ $import_status -ne 0 ]]; then
    if grep -qi "invalid attempt to delete cloudkit managed record type" "$log_file"; then
      echo "CloudKitSchema: import attempted to remove a CloudKit-managed type (for example cloudkit.share)." | tee -a "$log_file"
      echo "CloudKitSchema: validating that all contract record types already exist in Development and continuing." | tee -a "$log_file"

      run_export_development "$dev_export_ckdb_file" "$dev_export_log_file"

      expected_types_file="$tmp_dir/expected-types.txt"
      actual_types_file="$tmp_dir/actual-types.txt"
      jq -r '.recordTypes[].name' "$SCHEMA_JSON" | sort -u > "$expected_types_file"
      awk '/^[[:space:]]*RECORD TYPE[[:space:]]+/ {print $3}' "$dev_export_ckdb_file" | sort -u > "$actual_types_file"

      missing_contract_types="$(comm -23 "$expected_types_file" "$actual_types_file" || true)"
      if [[ -n "$missing_contract_types" ]]; then
        echo "CloudKitSchema: development schema is missing contract record type(s) after managed-type import failure:" >&2
        echo "$missing_contract_types" | sed 's/^/ - /' >&2
        exit 1
      fi

      echo "CloudKitSchema: development schema already satisfies contract types; proceeding." | tee -a "$log_file"
    else
      exit $import_status
    fi
  fi
fi

mkdir -p "$REPO_ROOT/cloudkit/artifacts"
cp "$ckdb_file" "$REPO_ROOT/cloudkit/artifacts/housepulse-schema.generated.ckdb"
if [[ -f "$log_file" ]]; then
  cp "$log_file" "$REPO_ROOT/cloudkit/artifacts/cktool-apply-development.log"
fi
if [[ -f "$dev_export_ckdb_file" ]]; then
  cp "$dev_export_ckdb_file" "$REPO_ROOT/cloudkit/artifacts/development-schema-export-after-apply.ckdb"
fi
if [[ -f "$dev_export_log_file" ]]; then
  cp "$dev_export_log_file" "$REPO_ROOT/cloudkit/artifacts/cktool-development-schema-export-after-apply.log"
fi

echo "CloudKitSchema: development schema apply finished."
