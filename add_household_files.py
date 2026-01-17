#!/usr/bin/env python3
"""Add household onboarding files to Xcode project"""

import re
import uuid

PROJECT_FILE = 'FamilyTodo.xcodeproj/project.pbxproj'

def generate_xcode_uuid():
    return uuid.uuid4().hex[:24].upper()

def main():
    with open(PROJECT_FILE, 'r') as f:
        content = f.read()

    # New files to add
    files = {
        'HouseholdStore.swift': {'group': 'Stores', 'path': 'Stores'},
        'OnboardingView.swift': {'group': 'Views', 'path': 'Views'},
    }

    # Generate UUIDs
    for filename, data in files.items():
        data['file_ref'] = generate_xcode_uuid()
        data['build_file'] = generate_xcode_uuid()

    # 1. Add PBXBuildFile entries
    build_section_end = content.find('/* End PBXBuildFile section */')
    build_entries = ''
    for filename, data in files.items():
        build_entries += f"\t\t{data['build_file']} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {data['file_ref']} /* {filename} */; }};\n"
    content = content[:build_section_end] + build_entries + content[build_section_end:]

    # 2. Add PBXFileReference entries
    file_ref_end = content.find('/* End PBXFileReference section */')
    file_ref_entries = ''
    for filename, data in files.items():
        file_ref_entries += f"\t\t{data['file_ref']} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};\n"
    content = content[:file_ref_end] + file_ref_entries + content[file_ref_end:]

    # 3. Find Stores and Views group UUIDs
    stores_uuid = re.search(r'(\w+) /\* Stores \*/ = \{', content).group(1)
    views_uuid = re.search(r'(\w+) /\* Views \*/ = \{', content).group(1)

    # 4. Add HouseholdStore.swift to Stores group
    stores_pattern = rf'({stores_uuid} /\* Stores \*/ = \{{\s*isa = PBXGroup;\s*children = \()'
    match = re.search(stores_pattern, content)
    if match:
        insert_pos = match.end()
        ref = files['HouseholdStore.swift']['file_ref']
        content = content[:insert_pos] + f"\n\t\t\t\t{ref} /* HouseholdStore.swift */," + content[insert_pos:]

    # 5. Add OnboardingView.swift to Views group
    views_pattern = rf'({views_uuid} /\* Views \*/ = \{{\s*isa = PBXGroup;\s*children = \()'
    match = re.search(views_pattern, content)
    if match:
        insert_pos = match.end()
        ref = files['OnboardingView.swift']['file_ref']
        content = content[:insert_pos] + f"\n\t\t\t\t{ref} /* OnboardingView.swift */," + content[insert_pos:]

    # 6. Add files to PBXSourcesBuildPhase
    sources_pattern = r'(isa = PBXSourcesBuildPhase;[^}]+files = \()'
    match = re.search(sources_pattern, content)
    if match:
        insert_pos = match.end()
        new_sources = ''
        for filename, data in files.items():
            new_sources += f"\n\t\t\t\t{data['build_file']} /* {filename} in Sources */,"
        content = content[:insert_pos] + new_sources + content[insert_pos:]

    with open(PROJECT_FILE, 'w') as f:
        f.write(content)

    print("✅ Added household files to Xcode project:")
    for filename, data in files.items():
        print(f"  - {data['path']}/{filename}")

if __name__ == '__main__':
    main()
