#!/bin/bash

# Script to add ShoppingListSettingsStore.swift to Xcode project
# This generates random UUIDs and adds the file to project.pbxproj

set -e

PROJECT_FILE="FamilyTodo.xcodeproj/project.pbxproj"
FILE_NAME="ShoppingListSettingsStore.swift"

# Generate two random 24-character hex UUIDs (Xcode style)
generate_uuid() {
    openssl rand -hex 12 | tr '[:lower:]' '[:upper:]'
}

FILE_REF_UUID=$(generate_uuid)
BUILD_FILE_UUID=$(generate_uuid)

echo "Generated UUIDs:"
echo "  File Reference UUID: $FILE_REF_UUID"
echo "  Build File UUID: $BUILD_FILE_UUID"

# Create backup
cp "$PROJECT_FILE" "$PROJECT_FILE.backup"

# We need to add entries in 4 sections:
# 1. PBXBuildFile section (near line 27)
# 2. PBXFileReference section (near line 92)
# 3. PBXGroup section (near line 303) 
# 4. PBXSourcesBuildPhase section (near line 403)

# Use sed to add entries after specific lines (using line numbers from grep results)

# 1. Add PBXBuildFile - add after line containing "E3C9F1B3FAE44A9A91D2F23C /* ShoppingListStore.swift in Sources */"
#    but only in the first occurrence (the definition, not the usage)
sed "27a\\
\\t\\t$BUILD_FILE_UUID /* $FILE_NAME in Sources */ = {isa = PBXBuildFile; fileRef = $FILE_REF_UUID /* $FILE_NAME */; };" "$PROJECT_FILE.backup" > "$PROJECT_FILE.tmp1"

# 2. Add PBXFileReference - add after the ShoppingListStore.swift file reference definition
sed "92a\\
\\t\\t$FILE_REF_UUID /* $FILE_NAME */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = $FILE_NAME; sourceTree = \"<group>\"; };" "$PROJECT_FILE.tmp1" > "$PROJECT_FILE.tmp2"

# 3. Add to PBXGroup (Stores) - add after ShoppingListStore in the group
sed "303a\\
\\t\\t\\t\\t$FILE_REF_UUID /* $FILE_NAME */," "$PROJECT_FILE.tmp2" > "$PROJECT_FILE.tmp3"

# 4. Add to PBXSourcesBuildPhase - add after ShoppingListStore in sources
sed "403a\\
\\t\\t\\t\\t$BUILD_FILE_UUID /* $FILE_NAME in Sources */," "$PROJECT_FILE.tmp3" > "$PROJECT_FILE"

# Clean up temp files
rm -f "$PROJECT_FILE.tmp1" "$PROJECT_FILE.tmp2" "$PROJECT_FILE.tmp3"

echo "✓ Successfully added $FILE_NAME to $PROJECT_FILE"
echo "Backup saved as $PROJECT_FILE.backup"

# Verify
echo ""
echo "Verification:"
grep -c "$FILE_NAME" "$PROJECT_FILE" || true
