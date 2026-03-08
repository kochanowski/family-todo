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

build_managed_safe_ckdb() {
  local desired_ckdb="$1"
  local development_ckdb="$2"
  local output_ckdb="$3"
  local log_file="$4"
  local merged_types_file="$5"

  cp "$desired_ckdb" "$output_ckdb"
  list_record_types_from_ckdb "$output_ckdb" > "$merged_types_file"

  local managed_type_names
  managed_type_names="$(list_record_types_from_ckdb "$development_ckdb" | grep '^cloudkit\.' || true)"

  if [[ -z "$managed_type_names" ]]; then
    echo "CloudKitSchema: no cloudkit.* managed record types found in Development export." | tee -a "$log_file"
    return 0
  fi

  while IFS= read -r managed_type; do
    [[ -z "$managed_type" ]] && continue
    if grep -Fxq "$managed_type" "$merged_types_file"; then
      continue
    fi

    {
      echo ""
      extract_record_type_block "$development_ckdb" "$managed_type"
    } >> "$output_ckdb"
    echo "$managed_type" >> "$merged_types_file"
    echo "CloudKitSchema: appended managed record type '$managed_type' to retry schema." | tee -a "$log_file"
  done <<< "$managed_type_names"
}

verify_contract_record_types_exist_in_development() {
  local schema_json="$1"
  local development_export_ckdb="$2"
  local tmp_dir="$3"
  local context_message="$4"

  local expected_types_file="$tmp_dir/expected-types.txt"
  local actual_types_file="$tmp_dir/actual-types.txt"
  jq -r '.recordTypes[].name' "$schema_json" | sort -u > "$expected_types_file"
  list_record_types_from_ckdb "$development_export_ckdb" > "$actual_types_file"

  local missing_contract_types
  missing_contract_types="$(comm -23 "$expected_types_file" "$actual_types_file" || true)"
  if [[ -n "$missing_contract_types" ]]; then
    echo "CloudKitSchema: development schema is missing contract record type(s) $context_message:" >&2
    echo "$missing_contract_types" | sed 's/^/ - /' >&2
    return 1
  fi

  return 0
}

list_field_signatures_from_ckdb() {
  local ckdb_file="$1"
  local include_record_types_file="$2"

  awk -v include_file="$include_record_types_file" '
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
      record_type = $3
      gsub(/"/, "", record_type)
      gsub(/\r/, "", record_type)
      in_record = (record_type in include)
      next
    }

    in_record && /^[[:space:]]*\);[[:space:]]*$/ {
      in_record = 0
      next
    }

    in_record {
      line = $0
      gsub(/\r/, "", line)

      if (line ~ /^[[:space:]]*"/) {
        sub(/^[[:space:]]*"/, "", line)
        split(line, segments, "\"")
        field_name = segments[1]
        flags = toupper(segments[2])
        gsub(/^[[:space:]]+/, "", flags)
        split(flags, flag_parts, /[[:space:]]+/)
        field_type = toupper(flag_parts[1])
        is_queryable = (index(flags, "QUERYABLE") > 0) ? 1 : 0
        is_sortable = (index(flags, "SORTABLE") > 0) ? 1 : 0
        print record_type "|" field_name "|" field_type "|" is_queryable "|" is_sortable
      }
    }
  ' "$ckdb_file" | sort -u
}

development_matches_contract_record_schema() {
  local schema_json="$1"
  local contract_ckdb="$2"
  local development_ckdb="$3"
  local tmp_dir="$4"

  local expected_types_file="$tmp_dir/expected-contract-types.txt"
  local expected_signatures_file="$tmp_dir/expected-contract-signatures.txt"
  local actual_signatures_file="$tmp_dir/actual-development-signatures.txt"

  jq -r '.recordTypes[].name' "$schema_json" | sort -u > "$expected_types_file"
  list_field_signatures_from_ckdb "$contract_ckdb" "$expected_types_file" > "$expected_signatures_file"
  list_field_signatures_from_ckdb "$development_ckdb" "$expected_types_file" > "$actual_signatures_file"

  cmp -s "$expected_signatures_file" "$actual_signatures_file"
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
    }
  ' "$ckdb_file" | sort -u
}

verify_required_security_role_permissions_in_development() {
  local schema_json="$1"
  local development_ckdb="$2"
  local tmp_dir="$3"

  local expected_permissions_file="$tmp_dir/expected-security-permissions.txt"
  local development_permissions_file="$tmp_dir/development-security-permissions.txt"

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

  list_security_role_permissions_from_ckdb "$development_ckdb" > "$development_permissions_file"

  if [[ ! -s "$development_permissions_file" ]]; then
    echo "CloudKitSchema: warning: development export does not include SECURITY ROLE blocks; skipping role verification." >&2
    echo "CloudKitSchema: manual check required in CloudKit Console -> Security Roles (InviteToken: _world=READ, _icloud=CREATE+READ, _creator=READ+WRITE)." >&2
    return 0
  fi

  local missing_permissions
  missing_permissions="$(comm -23 "$expected_permissions_file" "$development_permissions_file" || true)"
  if [[ -n "$missing_permissions" ]]; then
    echo "CloudKitSchema: development schema is missing required security role permission(s):" >&2
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
ckdb_file="$tmp_dir/schema.ckdb"
log_file="$tmp_dir/cktool-apply-development.log"
dev_export_ckdb_file="$tmp_dir/development-schema-export.ckdb"
dev_export_log_file="$tmp_dir/cktool-development-schema-export.log"
managed_retry_ckdb_file="$tmp_dir/schema-with-managed-types.ckdb"
managed_retry_log_file="$tmp_dir/cktool-apply-development-managed-retry.log"
merged_types_file="$tmp_dir/merged-types.txt"

render_ckdb "$SCHEMA_JSON" "$ckdb_file"

echo "CloudKitSchema: generated ckdb schema at $ckdb_file"

echo "CloudKitSchema: applying schema to development environment for container=$CONTAINER_ID"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "CloudKitSchema: DRY_RUN=true, skipping import-schema command."
else
  import_ckdb_file="$ckdb_file"
  skip_import=false
  import_executed=false
  set +e
  run_export_development "$dev_export_ckdb_file" "$dev_export_log_file"
  pre_export_status=$?
  set -e

  if [[ $pre_export_status -eq 0 ]]; then
    echo "CloudKitSchema: Development export succeeded. SECURITY ROLE blocks are not merged because cktool import-schema rejects SECURITY ROLE definitions." | tee -a "$log_file"
    if development_matches_contract_record_schema "$SCHEMA_JSON" "$import_ckdb_file" "$dev_export_ckdb_file" "$tmp_dir"; then
      echo "CloudKitSchema: development record schema already matches contract; skipping import to preserve Security Roles." | tee -a "$log_file"
      skip_import=true
    fi
  else
    echo "CloudKitSchema: warning: failed to export Development schema before import; proceeding without SECURITY ROLE preservation merge." | tee -a "$log_file"
  fi

  if [[ "$skip_import" != "true" ]]; then
    import_executed=true
    set +e
    run_import "$import_ckdb_file" "$log_file"
    import_status=$?
    set -e

    if [[ $import_status -ne 0 ]]; then
      if grep -qi "invalid attempt to delete cloudkit managed record type" "$log_file"; then
        echo "CloudKitSchema: import attempted to remove a CloudKit-managed type (for example cloudkit.share)." | tee -a "$log_file"
        echo "CloudKitSchema: exporting Development schema and retrying import with managed cloudkit.* record types preserved." | tee -a "$log_file"

        run_export_development "$dev_export_ckdb_file" "$dev_export_log_file"
        build_managed_safe_ckdb "$import_ckdb_file" "$dev_export_ckdb_file" "$managed_retry_ckdb_file" "$log_file" "$merged_types_file"

        set +e
        run_import "$managed_retry_ckdb_file" "$managed_retry_log_file"
        managed_retry_status=$?
        set -e

        if [[ $managed_retry_status -ne 0 ]]; then
          echo "CloudKitSchema: managed-type-safe retry import failed." >&2
          exit $managed_retry_status
        fi

        run_export_development "$dev_export_ckdb_file" "$dev_export_log_file"
        verify_contract_record_types_exist_in_development "$SCHEMA_JSON" "$dev_export_ckdb_file" "$tmp_dir" "after managed-type-safe retry"
        echo "CloudKitSchema: managed-type-safe retry succeeded and Development schema matches contract types." | tee -a "$log_file"
      else
        exit $import_status
      fi
    fi
  fi

  if [[ "$import_executed" == "true" || ! -f "$dev_export_ckdb_file" ]]; then
    run_export_development "$dev_export_ckdb_file" "$dev_export_log_file"
  fi
  verify_required_security_role_permissions_in_development "$SCHEMA_JSON" "$dev_export_ckdb_file" "$tmp_dir"
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
if [[ -f "$managed_retry_ckdb_file" ]]; then
  cp "$managed_retry_ckdb_file" "$REPO_ROOT/cloudkit/artifacts/housepulse-schema.managed-retry.ckdb"
fi
if [[ -f "$managed_retry_log_file" ]]; then
  cp "$managed_retry_log_file" "$REPO_ROOT/cloudkit/artifacts/cktool-apply-development-managed-retry.log"
fi

echo "CloudKitSchema: development schema apply finished."
