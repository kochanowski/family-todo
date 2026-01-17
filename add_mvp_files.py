#!/usr/bin/env python3
"""Add MVP files to Xcode project"""

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
        'CachedTask.swift': {'group': 'Models', 'path': 'Models'},
        'TaskStore.swift': {'group': 'Stores', 'path': 'Stores'},
        'TaskListView.swift': {'group': 'Views', 'path': 'Views'},
        'TaskDetailView.swift': {'group': 'Views', 'path': 'Views'},
    }

    # Generate UUIDs
    for filename, data in files.items():
        data['file_ref'] = generate_xcode_uuid()
        data['build_file'] = generate_xcode_uuid()

    # Stores group UUID
    stores_group_uuid = generate_xcode_uuid()

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

    # 3. Find Models and Views group UUIDs from file
    models_uuid = re.search(r'(\w+) /\* Models \*/ = \{', content).group(1)
    views_uuid = re.search(r'(\w+) /\* Views \*/ = \{', content).group(1)

    # 4. Add CachedTask.swift to Models group children
    models_pattern = rf'({models_uuid} /\* Models \*/ = \{{\s*isa = PBXGroup;\s*children = \()'
    match = re.search(models_pattern, content)
    if match:
        insert_pos = match.end()
        cached_task_ref = files['CachedTask.swift']['file_ref']
        content = content[:insert_pos] + f"\n\t\t\t\t{cached_task_ref} /* CachedTask.swift */," + content[insert_pos:]

    # 5. Add TaskListView.swift and TaskDetailView.swift to Views group children
    views_pattern = rf'({views_uuid} /\* Views \*/ = \{{\s*isa = PBXGroup;\s*children = \()'
    match = re.search(views_pattern, content)
    if match:
        insert_pos = match.end()
        list_view_ref = files['TaskListView.swift']['file_ref']
        detail_view_ref = files['TaskDetailView.swift']['file_ref']
        content = content[:insert_pos] + f"\n\t\t\t\t{list_view_ref} /* TaskListView.swift */,\n\t\t\t\t{detail_view_ref} /* TaskDetailView.swift */," + content[insert_pos:]

    # 6. Add Stores group to FamilyTodo children (after Views)
    familytodo_pattern = r'(A1B2C3D4E5F60718293A4B5D /\* FamilyTodo \*/ = \{[^}]+children = \([^)]+)(2253304769774D3792B036F0 /\* Views \*/,)'
    match = re.search(familytodo_pattern, content)
    if match:
        before = match.group(1)
        views_line = match.group(2)
        after = content[match.end():]
        content = content[:match.start()] + before + views_line + f"\n\t\t\t\t{stores_group_uuid} /* Stores */," + after

    # 7. Add Stores PBXGroup definition
    group_section_end = content.find('/* End PBXGroup section */')
    store_ref = files['TaskStore.swift']['file_ref']
    stores_group = f"""\t\t{stores_group_uuid} /* Stores */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{store_ref} /* TaskStore.swift */,
\t\t\t);
\t\t\tpath = Stores;
\t\t\tsourceTree = "<group>";
\t\t}};
"""
    content = content[:group_section_end] + stores_group + content[group_section_end:]

    # 8. Add files to PBXSourcesBuildPhase
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

    print("✅ Added MVP files to Xcode project:")
    for filename, data in files.items():
        print(f"  - {data['path']}/{filename}")

if __name__ == '__main__':
    main()
