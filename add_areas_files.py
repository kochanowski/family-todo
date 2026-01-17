#!/usr/bin/env python3
"""Add areas management files to Xcode project"""

import re
import uuid

PROJECT_FILE = 'FamilyTodo.xcodeproj/project.pbxproj'

def generate_xcode_uuid():
    return uuid.uuid4().hex[:24].upper()

def main():
    with open(PROJECT_FILE, 'r') as f:
        content = f.read()

    files = {
        'AreaStore.swift': {'group': 'Stores', 'path': 'Stores'},
        'AreasView.swift': {'group': 'Views', 'path': 'Views'},
    }

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

    # 3. Find group UUIDs
    stores_uuid = re.search(r'(\w+) /\* Stores \*/ = \{', content).group(1)
    views_uuid = re.search(r'(\w+) /\* Views \*/ = \{', content).group(1)

    # 4. Add to Stores group
    stores_pattern = rf'({stores_uuid} /\* Stores \*/ = \{{\s*isa = PBXGroup;\s*children = \()'
    match = re.search(stores_pattern, content)
    if match:
        insert_pos = match.end()
        ref = files['AreaStore.swift']['file_ref']
        content = content[:insert_pos] + f"\n\t\t\t\t{ref} /* AreaStore.swift */," + content[insert_pos:]

    # 5. Add to Views group
    views_pattern = rf'({views_uuid} /\* Views \*/ = \{{\s*isa = PBXGroup;\s*children = \()'
    match = re.search(views_pattern, content)
    if match:
        insert_pos = match.end()
        ref = files['AreasView.swift']['file_ref']
        content = content[:insert_pos] + f"\n\t\t\t\t{ref} /* AreasView.swift */," + content[insert_pos:]

    # 6. Add to PBXSourcesBuildPhase
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

    print("✅ Added areas files to Xcode project")

if __name__ == '__main__':
    main()
