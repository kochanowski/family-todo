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

    def permission_list:
      [
        if .create == true then "CREATE" else empty end,
        if .read == true then "READ" else empty end,
        if .write == true then "WRITE" else empty end
      ];

    def render_record_types:
      (
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
      );

    def render_security_roles:
      (
        (.securityRoles // [])
        | map(
            "SECURITY ROLE \(.name) (\n"
            + (
                .recordTypePermissions
                | map(
                    "  RECORD TYPE \"\(.recordType)\" "
                    + ((permission_list) | join(", "))
                  )
                | join(",\n")
              )
            + "\n);"
          )
        | join("\n\n")
      );

    "DEFINE SCHEMA\n"
    + render_record_types
    + (
        if ((.securityRoles // []) | length) > 0
        then "\n\n" + render_security_roles
        else ""
        end
      )
  ' "$input_json" > "$output_ckdb"
}

run_import() {
  local environment="$1"
  local ckdb_file="$2"
  local log_file="$3"

  if [[ -n "$TOKEN" ]]; then
    if xcrun cktool import-schema \
      --team-id "$TEAM_ID" \
      --container-id "$CONTAINER_ID" \
      --environment "$environment" \
      --file "$ckdb_file" \
      --token "$TOKEN" \
      2>&1 | tee "$log_file"; then
      return 0
    fi

    if grep -qi "unknown option.*--token" "$log_file"; then
      echo "CloudKitSchema: cktool does not support --token for import-schema; retrying without --token." | tee -a "$log_file"
    else
      return 1
    fi
  fi

  xcrun cktool import-schema \
    --team-id "$TEAM_ID" \
    --container-id "$CONTAINER_ID" \
    --environment "$environment" \
    --file "$ckdb_file" \
    2>&1 | tee "$log_file"
}

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

list_record_types_from_ckdb() {
  local ckdb_file="$1"
  awk '
    /^[[:space:]]*RECORD TYPE[[:space:]]+/ {
      name=$3
      gsub(/"/, "", name)
      gsub(/\r/, "", name)
      print name
    }
  ' "$ckdb_file" | sort -u
}

list_security_roles_from_ckdb() {
  local ckdb_file="$1"
  awk '
    /^[[:space:]]*SECURITY ROLE[[:space:]]+/ {
      name=$3
      gsub(/"/, "", name)
      gsub(/\r/, "", name)
      print name
    }
  ' "$ckdb_file" | sort -u
}

extract_record_type_block() {
  local ckdb_file="$1"
  local record_type_name="$2"

  awk -v target="$record_type_name" '
    function flush_block() {
      if (capture && type_name == target) {
        printf "%s", block
        found = 1
      }
      capture = 0
      block = ""
      type_name = ""
    }

    /^[[:space:]]*RECORD TYPE[[:space:]]+/ {
      flush_block()
      capture = 1
      block = $0 ORS
      type_name = $3
      gsub(/"/, "", type_name)
      gsub(/\r/, "", type_name)
      next
    }

    {
      if (capture) {
        block = block $0 ORS
        if ($0 ~ /^[[:space:]]*\);[[:space:]]*$/) {
          flush_block()
          if (found) {
            exit 0
          }
        }
      }
    }

    END {
      if (!found && capture && type_name == target) {
        printf "%s", block
        found = 1
      }
      if (!found) {
        exit 1
      }
    }
  ' "$ckdb_file"
}

extract_security_role_block() {
  local ckdb_file="$1"
  local role_name="$2"

  awk -v target="$role_name" '
    function flush_block() {
      if (capture && current_name == target) {
        printf "%s", block
        found = 1
      }
      capture = 0
      block = ""
      current_name = ""
    }

    /^[[:space:]]*SECURITY ROLE[[:space:]]+/ {
      flush_block()
      capture = 1
      block = $0 ORS
      current_name = $3
      gsub(/"/, "", current_name)
      gsub(/\r/, "", current_name)
      next
    }

    {
      if (capture) {
        block = block $0 ORS
        if ($0 ~ /^[[:space:]]*\);[[:space:]]*$/) {
          flush_block()
          if (found) {
            exit 0
          }
        }
      }
    }

    END {
      if (!found && capture && current_name == target) {
        printf "%s", block
        found = 1
      }
      if (!found) {
        exit 1
      }
    }
  ' "$ckdb_file"
}

build_role_safe_ckdb() {
  local desired_ckdb="$1"
  local export_ckdb="$2"
  local output_ckdb="$3"
  local log_file="$4"

  cp "$desired_ckdb" "$output_ckdb"

  local role_names
  role_names="$(list_security_roles_from_ckdb "$export_ckdb" || true)"
  if [[ -z "$role_names" ]]; then
    echo "CloudKitSchema: no SECURITY ROLE blocks found in environment export." | tee -a "$log_file"
    return 0
  fi

  while IFS= read -r role_name; do
    [[ -z "$role_name" ]] && continue

    if list_security_roles_from_ckdb "$output_ckdb" | grep -Fxq "$role_name"; then
      continue
    fi

    {
      echo ""
      extract_security_role_block "$export_ckdb" "$role_name"
    } >> "$output_ckdb"
    echo "CloudKitSchema: appended SECURITY ROLE '$role_name' to preserve existing access rules." | tee -a "$log_file"
  done <<< "$role_names"
}

build_managed_safe_ckdb() {
  local desired_ckdb="$1"
  local exported_ckdb="$2"
  local output_ckdb="$3"
  local log_file="$4"
  local merged_types_file="$5"

  cp "$desired_ckdb" "$output_ckdb"
  list_record_types_from_ckdb "$output_ckdb" > "$merged_types_file"

  local managed_type_names
  managed_type_names="$(list_record_types_from_ckdb "$exported_ckdb" | grep '^cloudkit\.' || true)"

  if [[ -z "$managed_type_names" ]]; then
    echo "CloudKitSchema: no cloudkit.* managed record types found in export." | tee -a "$log_file"
    return 0
  fi

  while IFS= read -r managed_type; do
    [[ -z "$managed_type" ]] && continue
    if grep -Fxq "$managed_type" "$merged_types_file"; then
      continue
    fi

    {
      echo ""
      extract_record_type_block "$exported_ckdb" "$managed_type"
    } >> "$output_ckdb"
    echo "$managed_type" >> "$merged_types_file"
    echo "CloudKitSchema: appended managed record type '$managed_type' to retry schema." | tee -a "$log_file"
  done <<< "$managed_type_names"
}

verify_required_record_types_in_production() {
  local schema_json="$1"
  local production_ckdb="$2"
  local development_ckdb="$3"
  local required_system_types="$4"
  local tmp_dir="$5"

  local expected_types_file="$tmp_dir/expected-types.txt"
  local required_types_file="$tmp_dir/required-types.txt"
  local production_types_file="$tmp_dir/production-types.txt"
  local development_types_file="$tmp_dir/development-types.txt"

  jq -r '.recordTypes[].name' "$schema_json" | sort -u > "$expected_types_file"
  {
    cat "$expected_types_file"
    tr ',' '\n' <<<"$required_system_types" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d'
  } | sort -u > "$required_types_file"
  list_record_types_from_ckdb "$production_ckdb" > "$production_types_file"
  list_record_types_from_ckdb "$development_ckdb" > "$development_types_file"

  local missing_types
  missing_types="$(comm -23 "$required_types_file" "$production_types_file" || true)"
  if [[ -z "$missing_types" ]]; then
    return 0
  fi

  echo "CloudKitSchema: production schema is missing required record type(s):" >&2
  echo "$missing_types" | sed 's/^/ - /' >&2

  while IFS= read -r missing_type; do
    [[ -z "$missing_type" ]] && continue
    if grep -Fxq "$missing_type" "$development_types_file"; then
      echo "CloudKitSchema: '$missing_type' exists in Development but not Production." >&2
      echo "CloudKitSchema: re-run this workflow to re-apply schema to Production." >&2
    else
      echo "CloudKitSchema: '$missing_type' is missing in Development too." >&2
      if [[ "$missing_type" == "cloudkit.share" ]]; then
        echo "CloudKitSchema: create at least one CKShare in Development first." >&2
      fi
    fi
  done <<< "$missing_types"

  return 1
}

list_security_role_permissions_from_ckdb() {
  local ckdb_file="$1"

  awk '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }

    /^[[:space:]]*SECURITY ROLE[[:space:]]+/ {
      role_name = $3
      gsub(/"/, "", role_name)
      gsub(/\r/, "", role_name)
      in_role = 1
      next
    }

    in_role && /^[[:space:]]*\);[[:space:]]*$/ {
      in_role = 0
      role_name = ""
      next
    }

    in_role && /^[[:space:]]*RECORD TYPE[[:space:]]+/ {
      line = $0
      if (match(line, /^[[:space:]]*RECORD TYPE[[:space:]]+"([^"]+)"[[:space:]]*(.*)$/, captures)) {
        record_type = captures[1]
        permissions_blob = captures[2]
        gsub(/\r/, "", permissions_blob)
        gsub(/[);]/, "", permissions_blob)
        split_count = split(permissions_blob, permissions, ",")
        for (index = 1; index <= split_count; index++) {
          permission = toupper(trim(permissions[index]))
          if (permission != "") {
            print role_name "|" record_type "|" permission
          }
        }
      }
    }
  ' "$ckdb_file" | sort -u
}

verify_required_security_role_permissions_in_production() {
  local schema_json="$1"
  local production_ckdb="$2"
  local tmp_dir="$3"

  local expected_permissions_file="$tmp_dir/expected-security-permissions.txt"
  local production_permissions_file="$tmp_dir/production-security-permissions.txt"

  jq -r '
    (.securityRoles // [])[] as $role
    | ($role.recordTypePermissions // [])[] as $permission
    | [
        if ($permission.create // false) then "CREATE" else empty end,
        if ($permission.read // false) then "READ" else empty end,
        if ($permission.write // false) then "WRITE" else empty end
      ][]
    | "\($role.name)|\($permission.recordType)|\(.)"
  ' "$schema_json" | sort -u > "$expected_permissions_file"

  list_security_role_permissions_from_ckdb "$production_ckdb" > "$production_permissions_file"

  local missing_permissions
  missing_permissions="$(comm -23 "$expected_permissions_file" "$production_permissions_file" || true)"
  if [[ -n "$missing_permissions" ]]; then
    echo "CloudKitSchema: production schema is missing required security role permission(s):" >&2
    echo "$missing_permissions" | sed 's/^/ - /' >&2
    return 1
  fi

  return 0
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
contract_ckdb_file="$tmp_dir/schema.ckdb"
apply_log_file="$tmp_dir/cktool-apply-production.log"
retry_ckdb_file="$tmp_dir/schema-with-managed-types.ckdb"
role_safe_ckdb_file="$tmp_dir/schema-with-security-roles.ckdb"
retry_log_file="$tmp_dir/cktool-apply-production-managed-retry.log"
merged_types_file="$tmp_dir/merged-types.txt"
prod_before_ckdb_file="$tmp_dir/production-schema-before.ckdb"
prod_before_log_file="$tmp_dir/cktool-production-schema-before.log"
prod_ckdb_file="$tmp_dir/production-schema.ckdb"
prod_log_file="$tmp_dir/cktool-production-schema-after.log"
dev_ckdb_file="$tmp_dir/development-schema.ckdb"
dev_log_file="$tmp_dir/cktool-development-schema-after.log"

mkdir -p "$REPO_ROOT/cloudkit/artifacts"
render_ckdb "$SCHEMA_JSON" "$contract_ckdb_file"

echo "CloudKitSchema: applying schema to production environment for container=$CONTAINER_ID"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "CloudKitSchema: DRY_RUN=true, skipping production import and verification."
  exit 0
fi

import_ckdb_file="$contract_ckdb_file"
set +e
run_export production "$prod_before_ckdb_file" "$prod_before_log_file"
pre_export_status=$?
set -e

if [[ $pre_export_status -eq 0 ]]; then
  build_role_safe_ckdb "$contract_ckdb_file" "$prod_before_ckdb_file" "$role_safe_ckdb_file" "$apply_log_file"
  import_ckdb_file="$role_safe_ckdb_file"
else
  echo "CloudKitSchema: warning: failed to export Production schema before import; proceeding without SECURITY ROLE preservation merge." | tee -a "$apply_log_file"
fi

set +e
run_import production "$import_ckdb_file" "$apply_log_file"
import_status=$?
set -e

if [[ $import_status -ne 0 ]]; then
  if grep -qi "endpoint not applicable in the environment 'production'" "$apply_log_file"; then
    echo "CloudKitSchema: production import endpoint is not available for this token/cktool mode." | tee -a "$apply_log_file"
    echo "CloudKitSchema: switching to verification-only mode for Production." | tee -a "$apply_log_file"
  elif grep -qi "invalid attempt to delete cloudkit managed record type" "$apply_log_file"; then
    echo "CloudKitSchema: production import attempted to remove CloudKit-managed type(s); retrying with managed cloudkit.* record types preserved." | tee -a "$apply_log_file"
    if [[ $pre_export_status -ne 0 ]]; then
      run_export production "$prod_before_ckdb_file" "$prod_before_log_file"
    fi
    build_managed_safe_ckdb "$import_ckdb_file" "$prod_before_ckdb_file" "$retry_ckdb_file" "$apply_log_file" "$merged_types_file"

    set +e
    run_import production "$retry_ckdb_file" "$retry_log_file"
    retry_status=$?
    set -e
    if [[ $retry_status -ne 0 ]]; then
      echo "CloudKitSchema: production managed-type-safe retry import failed." >&2
      exit $retry_status
    fi
  else
    exit $import_status
  fi
fi

run_export production "$prod_ckdb_file" "$prod_log_file"
run_export development "$dev_ckdb_file" "$dev_log_file"

cp "$prod_ckdb_file" "$REPO_ROOT/cloudkit/artifacts/production-schema-export.ckdb"
cp "$dev_ckdb_file" "$REPO_ROOT/cloudkit/artifacts/development-schema-export.ckdb"
cp "$contract_ckdb_file" "$REPO_ROOT/cloudkit/artifacts/housepulse-schema.generated.ckdb"
if [[ -f "$prod_log_file" ]]; then
  cp "$prod_log_file" "$REPO_ROOT/cloudkit/artifacts/cktool-production-schema-check.log"
fi
if [[ -f "$dev_log_file" ]]; then
  cp "$dev_log_file" "$REPO_ROOT/cloudkit/artifacts/cktool-development-schema-check.log"
fi
if [[ -f "$apply_log_file" ]]; then
  cp "$apply_log_file" "$REPO_ROOT/cloudkit/artifacts/cktool-apply-production.log"
fi
if [[ -f "$retry_log_file" ]]; then
  cp "$retry_log_file" "$REPO_ROOT/cloudkit/artifacts/cktool-apply-production-managed-retry.log"
fi
if [[ -f "$retry_ckdb_file" ]]; then
  cp "$retry_ckdb_file" "$REPO_ROOT/cloudkit/artifacts/housepulse-schema.production-managed-retry.ckdb"
fi
if [[ -f "$role_safe_ckdb_file" ]]; then
  cp "$role_safe_ckdb_file" "$REPO_ROOT/cloudkit/artifacts/housepulse-schema.production-role-safe.ckdb"
fi

verify_required_record_types_in_production "$SCHEMA_JSON" "$prod_ckdb_file" "$dev_ckdb_file" "$REQUIRED_SYSTEM_TYPES" "$tmp_dir"
verify_required_security_role_permissions_in_production "$SCHEMA_JSON" "$prod_ckdb_file" "$tmp_dir"

echo "CloudKitSchema: production schema contains all required record types (including system types: $REQUIRED_SYSTEM_TYPES) and required security role permissions."
