#!/usr/bin/env bash
set -euo pipefail

SCHEMA_FILE="${1:-cloudkit/schema/housepulse-schema.json}"
EXPECTED_CONTAINER="${CONTAINER_ID:-iCloud.com.kochanowski.housepulse}"

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "CloudKitSchema: schema file not found: $SCHEMA_FILE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "CloudKitSchema: jq is required for schema validation." >&2
  exit 1
fi

jq -e '.' "$SCHEMA_FILE" >/dev/null

container_id="$(jq -r '.containerIdentifier // empty' "$SCHEMA_FILE")"
if [[ -z "$container_id" ]]; then
  echo "CloudKitSchema: missing containerIdentifier in $SCHEMA_FILE" >&2
  exit 1
fi

if [[ "$container_id" != "$EXPECTED_CONTAINER" ]]; then
  echo "CloudKitSchema: containerIdentifier mismatch. expected=$EXPECTED_CONTAINER got=$container_id" >&2
  exit 1
fi

if [[ "$(jq -r '(.recordTypes | type) // ""' "$SCHEMA_FILE")" != "array" ]]; then
  echo "CloudKitSchema: recordTypes must be an array." >&2
  exit 1
fi

allowed_types='["String","Int64","Date","Reference","ReferenceList"]'
invalid_types="$(jq -r --argjson allowed "$allowed_types" '
  .recordTypes[]
  | .name as $record
  | .fields[]
  | select((.type | IN($allowed[])) | not)
  | "\($record).\(.name):\(.type)"
' "$SCHEMA_FILE")"
if [[ -n "$invalid_types" ]]; then
  echo "CloudKitSchema: unsupported field types found:" >&2
  echo "$invalid_types" >&2
  exit 1
fi

duplicate_record_types="$(jq -r '.recordTypes[].name' "$SCHEMA_FILE" | sort | uniq -d)"
if [[ -n "$duplicate_record_types" ]]; then
  echo "CloudKitSchema: duplicate record type names:" >&2
  echo "$duplicate_record_types" >&2
  exit 1
fi

duplicate_fields="$(jq -r '
  .recordTypes[]
  | .name as $record
  | [.fields[].name]
  | group_by(.)
  | map(select(length > 1) | .[0])
  | .[]?
  | "\($record).\(.)"
' "$SCHEMA_FILE")"
if [[ -n "$duplicate_fields" ]]; then
  echo "CloudKitSchema: duplicate field names in record types:" >&2
  echo "$duplicate_fields" >&2
  exit 1
fi

required_map='{
  "Household": ["id", "name", "colorHex", "iconSymbol", "ownerId", "createdAt", "updatedAt"],
  "Member": ["id", "householdId", "userId", "displayName", "colorHex", "role", "joinedAt", "isActive"],
  "Area": ["id", "householdId", "name", "icon", "sortOrder", "createdAt"],
  "Task": ["id", "householdId", "title", "status", "assigneeId", "assigneeIds", "backlogCategoryId", "areaId", "dueDate", "completedAt", "completedById", "taskType", "recurringChoreId", "notes", "createdAt", "updatedAt"],
  "RecurringChore": ["id", "householdId", "title", "recurrenceType", "recurrenceDay", "recurrenceDayOfMonth", "recurrenceInterval", "defaultAssigneeIds", "defaultAssigneeId", "areaId", "categoryId", "isActive", "lastGeneratedDate", "nextScheduledDate", "notes", "createdAt", "updatedAt"],
  "ShoppingItem": ["id", "householdId", "title", "quantityValue", "quantityUnit", "isBought", "boughtAt", "restockCount", "sortOrder", "createdAt", "updatedAt"],
  "BacklogCategory": ["id", "householdId", "title", "sortOrder", "createdAt", "updatedAt"],
  "BacklogItem": ["id", "categoryId", "householdId", "title", "assigneeId", "notes", "createdAt", "updatedAt"],
  "InviteToken": ["code", "householdId", "shareURL", "createdAt", "expiresAt", "isRevoked", "usesCount", "lastRedeemedAt"]
}'

required_indexes='{
  "Household": { "query": ["id"], "sort": [] },
  "Member": { "query": ["householdId", "userId"], "sort": ["joinedAt"] },
  "Area": { "query": ["householdId"], "sort": ["sortOrder"] },
  "Task": { "query": ["householdId", "status", "assigneeId"], "sort": ["updatedAt"] },
  "RecurringChore": { "query": ["householdId"], "sort": ["title"] },
  "ShoppingItem": { "query": ["householdId"], "sort": ["sortOrder"] },
  "BacklogCategory": { "query": ["householdId"], "sort": ["sortOrder"] },
  "BacklogItem": { "query": ["householdId", "categoryId"], "sort": ["createdAt"] },
  "InviteToken": { "query": ["code", "householdId", "isRevoked", "expiresAt"], "sort": ["createdAt"] }
}'

errors=()

while IFS= read -r record_type; do
  [[ -z "$record_type" ]] && continue

  exists="$(jq -r --arg rt "$record_type" 'any(.recordTypes[]; .name == $rt)' "$SCHEMA_FILE")"
  if [[ "$exists" != "true" ]]; then
    errors+=("missing record type: $record_type")
    continue
  fi

  while IFS= read -r field; do
    [[ -z "$field" ]] && continue
    has_field="$(jq -r --arg rt "$record_type" --arg f "$field" 'any(.recordTypes[] | select(.name == $rt) | .fields[]; .name == $f)' "$SCHEMA_FILE")"
    if [[ "$has_field" != "true" ]]; then
      errors+=("missing field: $record_type.$field")
    fi
  done < <(jq -r --arg rt "$record_type" --argjson m "$required_map" '$m[$rt][]' < /dev/null)

  for index_kind in query sort; do
    while IFS= read -r indexed_field; do
      [[ -z "$indexed_field" ]] && continue

      has_index="$(jq -r --arg rt "$record_type" --arg k "$index_kind" --arg f "$indexed_field" '
        any(.recordTypes[] | select(.name == $rt) | (.indexes[$k] // [] )[]; . == $f)
      ' "$SCHEMA_FILE")"
      if [[ "$has_index" != "true" ]]; then
        errors+=("missing $index_kind index declaration: $record_type.$indexed_field")
      fi

      if [[ "$index_kind" == "query" ]]; then
        flag_name="queryable"
      else
        flag_name="sortable"
      fi

      field_marked="$(jq -r --arg rt "$record_type" --arg f "$indexed_field" --arg flag "$flag_name" '
        any(.recordTypes[] | select(.name == $rt) | .fields[]; .name == $f and (.[ $flag ] == true))
      ' "$SCHEMA_FILE")"
      if [[ "$field_marked" != "true" ]]; then
        errors+=("field flag mismatch: $record_type.$indexed_field should have $flag_name=true")
      fi
    done < <(jq -r --arg rt "$record_type" --arg k "$index_kind" --argjson m "$required_indexes" '$m[$rt][$k][]?' < /dev/null)
  done

done < <(jq -r --argjson m "$required_map" '$m | keys[]' < /dev/null)

if (( ${#errors[@]} > 0 )); then
  echo "CloudKitSchema: validation failed with ${#errors[@]} issue(s):" >&2
  printf ' - %s\n' "${errors[@]}" >&2
  exit 1
fi

record_count="$(jq '.recordTypes | length' "$SCHEMA_FILE")"
field_count="$(jq '[.recordTypes[].fields[]] | length' "$SCHEMA_FILE")"

echo "CloudKitSchema: validation passed. container=$container_id recordTypes=$record_count fields=$field_count"
