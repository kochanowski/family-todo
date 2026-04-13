#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCHEMA_JSON="${1:-$REPO_ROOT/cloudkit/schema/housepulse-schema.json}"
TEAM_ID="${TEAM_ID:-}"
CONTAINER_ID="${CONTAINER_ID:-iCloud.com.kochanowski.housepulse}"
TOKEN="${CLOUDKIT_MANAGEMENT_TOKEN:-}"

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

list_field_signatures_from_ckdb() {
  local ckdb_file="$1"
  local include_record_types_file="$2"

  awk -v include_file="$include_record_types_file" '
    function trim(value) {
      gsub(/^[[:space:]]+/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      return value
    }

    BEGIN {
      while ((getline line < include_file) > 0) {
        gsub(/\r/, "", line)
        if (line != "") {
          include[line] = 1
        }
      }
      close(include_file)
    }

    /^[[:space:]]*RECORD TYPE[[:space:]]+/ {
      line = $0
      sub(/^[[:space:]]*RECORD TYPE[[:space:]]+/, "", line)
      split(line, parts, /\(/)
      record_type = trim(parts[1])
      gsub(/"/, "", record_type)
      gsub(/\r/, "", record_type)
      in_record = (record_type in include)
      next
    }

    in_record && /^[[:space:]]*\);[[:space:]]*$/ {
      in_record = 0
      next
    }

    !in_record {
      next
    }

    {
      line = $0
      gsub(/\r/, "", line)
      line = trim(line)
      sub(/,[[:space:]]*$/, "", line)

      if (line == "" || line ~ /^GRANT[[:space:]]+/) {
        next
      }

      field_name = ""
      rest = ""

      if (substr(line, 1, 1) == "\"") {
        line = substr(line, 2)
        split(line, quoted_parts, "\"")
        field_name = quoted_parts[1]
        rest = substr(line, length(field_name) + 2)
      } else {
        split(line, plain_parts, /[[:space:]]+/)
        field_name = plain_parts[1]
        rest = substr(line, length(field_name) + 1)
      }

      field_name = trim(field_name)
      rest = toupper(trim(rest))
      if (field_name == "" || rest == "") {
        next
      }

      split(rest, tokens, /[[:space:]]+/)
      field_type = tokens[1]
      is_queryable = (rest ~ /(^|[[:space:]])QUERYABLE([[:space:]]|$)/) ? 1 : 0
      is_sortable = (rest ~ /(^|[[:space:]])SORTABLE([[:space:]]|$)/) ? 1 : 0
      print record_type "|" field_name "|" field_type "|" is_queryable "|" is_sortable
    }
  ' "$ckdb_file" | sort -u
}

filter_signatures_to_expected_keys() {
  local signatures_file="$1"
  local expected_keys_file="$2"

  awk -F'|' '
    BEGIN {
      while ((getline line < ARGV[1]) > 0) {
        gsub(/\r/, "", line)
        if (line != "") {
          expected[line] = 1
        }
      }
      close(ARGV[1])
    }

    {
      key = $1 "|" $2
      if (key in expected) {
        print
      }
    }
  ' "$expected_keys_file" "$signatures_file" | sort -u
}

list_security_role_permissions_from_ckdb() {
  local ckdb_file="$1"

  awk '
    function trim(value) {
      gsub(/^[[:space:]]+/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      return value
    }

    /^[[:space:]]*SECURITY ROLE[[:space:]]+/ {
      in_record = 0
      record_type = ""
      role_name = $3
      gsub(/"/, "", role_name)
      gsub(/\r/, "", role_name)
      in_role = 1
      next
    }

    /^[[:space:]]*RECORD TYPE[[:space:]]+/ {
      if (in_role) {
        line = $0
        sub(/^[[:space:]]*RECORD TYPE[[:space:]]+"/, "", line)
        split(line, segments, "\"")
        record_type = trim(segments[1])
        permissions_blob = segments[2]
        gsub(/\r/, "", permissions_blob)
        gsub(/[);]/, "", permissions_blob)
        split_count = split(permissions_blob, permissions, ",")
        for (idx = 1; idx <= split_count; idx++) {
          permission = toupper(trim(permissions[idx]))
          if (permission != "") {
            print role_name "|" record_type "|" permission
          }
        }
        next
      }

      role_name = ""
      in_role = 0
      record_type = $3
      gsub(/"/, "", record_type)
      gsub(/\r/, "", record_type)
      in_record = 1
      next
    }

    in_role && /^[[:space:]]*\);[[:space:]]*$/ {
      in_role = 0
      role_name = ""
      next
    }

    in_record && /^[[:space:]]*\);[[:space:]]*$/ {
      in_record = 0
      record_type = ""
      next
    }

    in_record && /^[[:space:]]*GRANT[[:space:]]+/ {
      line = $0
      gsub(/\r/, "", line)
      sub(/^[[:space:]]*GRANT[[:space:]]+/, "", line)
      split(line, segments, /[[:space:]]+TO[[:space:]]+"/)
      permission = toupper(trim(segments[1]))
      role = trim(segments[2])
      sub(/".*$/, "", role)
      gsub(/[,)]/, "", role)
      if (permission != "" && role != "") {
        print role "|" record_type "|" permission
      }
    }
  ' "$ckdb_file" | sort -u
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

expected_signatures_file="$tmp_dir/expected-signatures.txt"
expected_record_types_file="$tmp_dir/expected-record-types.txt"
expected_keys_file="$tmp_dir/expected-keys.txt"
expected_permissions_file="$tmp_dir/expected-permissions.txt"

development_ckdb_file="$tmp_dir/development-schema.ckdb"
development_log_file="$tmp_dir/cktool-development-schema-export.log"
development_signatures_all_file="$tmp_dir/development-signatures-all.txt"
development_signatures_file="$tmp_dir/development-signatures.txt"
development_permissions_file="$tmp_dir/development-permissions.txt"

production_ckdb_file="$tmp_dir/production-schema.ckdb"
production_log_file="$tmp_dir/cktool-production-schema-export.log"
production_signatures_all_file="$tmp_dir/production-signatures-all.txt"
production_signatures_file="$tmp_dir/production-signatures.txt"
production_permissions_file="$tmp_dir/production-permissions.txt"

jq -r '
  .recordTypes[]
  | .name as $record_type
  | .fields[]
  | [
      $record_type,
      .name,
      (if .type == "String" then "STRING"
       elif .type == "Int64" then "INT64"
       elif .type == "Date" then "TIMESTAMP"
       elif .type == "Reference" then "REFERENCE"
       elif .type == "ReferenceList" then "LIST<REFERENCE>"
       else "UNKNOWN" end),
      (if .queryable then "1" else "0" end),
      (if .sortable then "1" else "0" end)
    ]
  | join("|")
' "$SCHEMA_JSON" | sort -u > "$expected_signatures_file"

cut -d'|' -f1 "$expected_signatures_file" | sort -u > "$expected_record_types_file"
cut -d'|' -f1,2 "$expected_signatures_file" | sort -u > "$expected_keys_file"

jq -r '
  (.securityRoles // [])[] as $role
  | ($role.recordTypePermissions // [])[] as $permission
  | [
      if ($permission.create // false) then "CREATE" else empty end,
      if ($permission.read // false) then "READ" else empty end,
      if ($permission.write // false) then "WRITE" else empty end
    ][]
  | "\($role.name)|\($permission.recordType)|\(.)"
' "$SCHEMA_JSON" | sort -u > "$expected_permissions_file"

echo "CloudKitSchema: exporting Development schema for parity verification."
run_export development "$development_ckdb_file" "$development_log_file"
list_field_signatures_from_ckdb "$development_ckdb_file" "$expected_record_types_file" > "$development_signatures_all_file"
filter_signatures_to_expected_keys "$development_signatures_all_file" "$expected_keys_file" > "$development_signatures_file"
list_security_role_permissions_from_ckdb "$development_ckdb_file" > "$development_permissions_file"

echo "CloudKitSchema: exporting Production schema for parity verification."
run_export production "$production_ckdb_file" "$production_log_file"
list_field_signatures_from_ckdb "$production_ckdb_file" "$expected_record_types_file" > "$production_signatures_all_file"
filter_signatures_to_expected_keys "$production_signatures_all_file" "$expected_keys_file" > "$production_signatures_file"
list_security_role_permissions_from_ckdb "$production_ckdb_file" > "$production_permissions_file"

missing_in_development="$(comm -23 "$expected_signatures_file" "$development_signatures_file" || true)"
if [[ -n "$missing_in_development" ]]; then
  echo "CloudKitSchema: Development schema is missing expected contract field signature(s):" >&2
  echo "$missing_in_development" | sed 's/^/ - /' >&2
  exit 1
fi

missing_in_production="$(comm -23 "$expected_signatures_file" "$production_signatures_file" || true)"
if [[ -n "$missing_in_production" ]]; then
  echo "CloudKitSchema: Production schema is missing expected contract field signature(s):" >&2
  echo "$missing_in_production" | sed 's/^/ - /' >&2
  exit 1
fi

field_parity_diff="$(comm -3 "$development_signatures_file" "$production_signatures_file" || true)"
if [[ -n "$field_parity_diff" ]]; then
  echo "CloudKitSchema: Development and Production signatures diverge for contract fields:" >&2
  echo "$field_parity_diff" | sed 's/^/ - /' >&2
  exit 1
fi

is_premium_signature="$(awk -F'|' '$1 == "Household" && $2 == "isPremium" { print; exit }' "$expected_signatures_file")"
if [[ -z "$is_premium_signature" ]]; then
  echo "CloudKitSchema: contract is missing required field signature Household.isPremium." >&2
  exit 1
fi

if ! grep -Fxq "$is_premium_signature" "$development_signatures_file"; then
  echo "CloudKitSchema: Development schema is missing Household.isPremium." >&2
  exit 1
fi

if ! grep -Fxq "$is_premium_signature" "$production_signatures_file"; then
  echo "CloudKitSchema: Production schema is missing Household.isPremium." >&2
  exit 1
fi

missing_permissions_development="$(comm -23 "$expected_permissions_file" "$development_permissions_file" || true)"
if [[ -n "$missing_permissions_development" ]]; then
  echo "CloudKitSchema: Development schema is missing required security role permission(s):" >&2
  echo "$missing_permissions_development" | sed 's/^/ - /' >&2
  exit 1
fi

missing_permissions_production="$(comm -23 "$expected_permissions_file" "$production_permissions_file" || true)"
if [[ -n "$missing_permissions_production" ]]; then
  echo "CloudKitSchema: Production schema is missing required security role permission(s):" >&2
  echo "$missing_permissions_production" | sed 's/^/ - /' >&2
  exit 1
fi

permission_parity_diff="$(comm -3 "$development_permissions_file" "$production_permissions_file" || true)"
if [[ -n "$permission_parity_diff" ]]; then
  echo "CloudKitSchema: Development and Production security permissions diverge:" >&2
  echo "$permission_parity_diff" | sed 's/^/ - /' >&2
  exit 1
fi

mkdir -p "$REPO_ROOT/cloudkit/artifacts"
cp "$expected_signatures_file" "$REPO_ROOT/cloudkit/artifacts/contract-field-signatures.txt"
cp "$development_signatures_file" "$REPO_ROOT/cloudkit/artifacts/development-field-signatures.txt"
cp "$production_signatures_file" "$REPO_ROOT/cloudkit/artifacts/production-field-signatures.txt"
cp "$expected_permissions_file" "$REPO_ROOT/cloudkit/artifacts/contract-security-permissions.txt"
cp "$development_permissions_file" "$REPO_ROOT/cloudkit/artifacts/development-security-permissions.txt"
cp "$production_permissions_file" "$REPO_ROOT/cloudkit/artifacts/production-security-permissions.txt"
cp "$development_ckdb_file" "$REPO_ROOT/cloudkit/artifacts/development-schema-export-parity.ckdb"
cp "$production_ckdb_file" "$REPO_ROOT/cloudkit/artifacts/production-schema-export-parity.ckdb"
cp "$development_log_file" "$REPO_ROOT/cloudkit/artifacts/cktool-development-schema-export-parity.log"
cp "$production_log_file" "$REPO_ROOT/cloudkit/artifacts/cktool-production-schema-export-parity.log"

echo "CloudKitSchema: parity verification passed for container=$CONTAINER_ID."
