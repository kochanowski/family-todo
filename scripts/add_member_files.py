import uuid
import re
import os

PROJECT_PATH = 'FamilyTodo.xcodeproj/project.pbxproj'

# IDs
MODELS_GROUP_ID = 'A1B2C3D4E5F60718293A4B9A'
STORES_GROUP_ID = 'FA1C0439FFD449E092083889'
VIEWS_GROUP_ID = '2253304769774D3792B036F0'
SOURCES_BUILD_PHASE_ID = 'A1B2C3D4E5F60718293A4B6B'

# Files to add
FILES = [
    {'path': 'Household.swift', 'group_id': MODELS_GROUP_ID, 'full_path': 'FamilyTodo/Models/Household.swift'},
    {'path': 'CachedHousehold.swift', 'group_id': MODELS_GROUP_ID, 'full_path': 'FamilyTodo/Models/CachedHousehold.swift'},
    {'path': 'HouseholdStore.swift', 'group_id': STORES_GROUP_ID, 'full_path': 'FamilyTodo/Stores/HouseholdStore.swift'},
    {'path': 'MemberStore.swift', 'group_id': STORES_GROUP_ID, 'full_path': 'FamilyTodo/Stores/MemberStore.swift'},
    {'path': 'ShareInviteView.swift', 'group_id': VIEWS_GROUP_ID, 'full_path': 'FamilyTodo/Views/ShareInviteView.swift'},
]

def generate_id():
    return uuid.uuid4().hex[:24].upper()

def main():
    with open(PROJECT_PATH, 'r') as f:
        content = f.read()

    # Calculate IDs
    new_entries = []
    for file in FILES:
        file['fileRef'] = generate_id()
        file['buildFile'] = generate_id()
        new_entries.append(file)
        print(f"Prepared to add {file['path']}")

    # 1. Add PBXBuildFile entries
    build_files_section = ""
    for file in new_entries:
        entry = f'\t\t{file["buildFile"]} /* {file["path"]} in Sources */ = {{isa = PBXBuildFile; fileRef = {file["fileRef"]} /* {file["path"]} */; }};\n'
        build_files_section += entry
    
    # Insert at beginning of PBXBuildFile section
    content = content.replace('/* Begin PBXBuildFile section */\n', '/* Begin PBXBuildFile section */\n' + build_files_section)

    # 2. Add PBXFileReference entries
    file_refs_section = ""
    for file in new_entries:
        entry = f'\t\t{file["fileRef"]} /* {file["path"]} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file["path"]}; sourceTree = "<group>"; }};\n'
        file_refs_section += entry
        
    # Insert at beginning of PBXFileReference section
    content = content.replace('/* Begin PBXFileReference section */\n', '/* Begin PBXFileReference section */\n' + file_refs_section)

    # 3. Add to Groups
    for file in new_entries:
        group_id = file['group_id']
        # Find group definition
        # Regex to find group children list
        # We look for group_id ... children = ( ... );
        pattern = re.compile(rf'{group_id} /\* .*? \*/ = {{\n\s*isa = PBXGroup;\n\s*children = \(\n', re.DOTALL)
        match = pattern.search(content)
        if match:
            # Insert after children = (\n
            insert_pos = match.end()
            entry = f'\t\t\t\t{file["fileRef"]} /* {file["path"]} */,\n'
            content = content[:insert_pos] + entry + content[insert_pos:]
        else:
            print(f"Error: Group {group_id} not found for {file['path']}")

    # 4. Add to Sources Build Phase
    # Find Sources Build Phase
    pattern = re.compile(rf'{SOURCES_BUILD_PHASE_ID} /\* Sources \*/ = {{\n\s*isa = PBXSourcesBuildPhase;\n\s*buildActionMask = \d+;\n\s*files = \(\n', re.DOTALL)
    match = pattern.search(content)
    if match:
         insert_pos = match.end()
         entries = ""
         for file in new_entries:
             entries += f'\t\t\t\t{file["buildFile"]} /* {file["path"]} in Sources */,\n'
         content = content[:insert_pos] + entries + content[insert_pos:]
    else:
        print(f"Error: Sources Build Phase {SOURCES_BUILD_PHASE_ID} not found")

    with open(PROJECT_PATH, 'w') as f:
        f.write(content)
    
    print("Successfully updated project.pbxproj")

if __name__ == '__main__':
    main()
