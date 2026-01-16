#!/usr/bin/env python3
"""Simple script to add new Swift files to Xcode project"""

import re
import uuid

PROJECT_FILE = 'FamilyTodo.xcodeproj/project.pbxproj'

# New files to add
NEW_FILES = {
    'AuthenticationService.swift': 'Services',
    'UserSession.swift': 'Services',
    'SignInView.swift': 'Views',
}

def generate_xcode_uuid():
    """Generate 24-character hex UUID similar to Xcode format"""
    return uuid.uuid4().hex[:24].upper()

def main():
    with open(PROJECT_FILE, 'r') as f:
        content = f.read()

    # Generate UUIDs for each file
    file_data = {}
    for filename, group in NEW_FILES.items():
        file_data[filename] = {
            'file_ref_uuid': generate_xcode_uuid(),
            'build_file_uuid': generate_xcode_uuid(),
            'group': group,
        }

    # Generate UUIDs for new groups
    services_group_uuid = generate_xcode_uuid()
    views_group_uuid = generate_xcode_uuid()

    # 1. Add PBXBuildFile entries
    build_file_section_end = content.find('/* End PBXBuildFile section */')
    build_file_entries = []
    for filename, data in file_data.items():
        entry = f"\t\t{data['build_file_uuid']} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {data['file_ref_uuid']} /* {filename} */; }};\n"
        build_file_entries.append(entry)

    content = content[:build_file_section_end] + ''.join(build_file_entries) + content[build_file_section_end:]

    # 2. Add PBXFileReference entries
    file_ref_section_end = content.find('/* End PBXFileReference section */')
    file_ref_entries = []
    for filename, data in file_data.items():
        entry = f"\t\t{data['file_ref_uuid']} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};\n"
        file_ref_entries.append(entry)

    content = content[:file_ref_section_end] + ''.join(file_ref_entries) + content[file_ref_section_end:]

    # 3. Add Services and Views groups to FamilyTodo group children
    familytodo_group_pattern = r'(A1B2C3D4E5F60718293A4B5D /\* FamilyTodo \*/ = \{[^}]+children = \([^)]+)(A1B2C3D4E5F60718293A4B9D /\* Managers \*/,)'
    match = re.search(familytodo_group_pattern, content, re.DOTALL)
    if match:
        before = match.group(1)
        managers_line = match.group(2)
        after = content[match.end():]

        # Add Services and Views before Managers
        new_children = f"{before}\t\t\t\t{services_group_uuid} /* Services */,\n\t\t\t\t{views_group_uuid} /* Views */,\n\t\t\t\t{managers_line}{after}"
        content = content[:match.start()] + new_children

    # 4. Add Services and Views PBXGroup definitions
    group_section_end = content.find('/* End PBXGroup section */')

    services_children = '\n'.join([
        f"\t\t\t\t{data['file_ref_uuid']} /* {filename} */,"
        for filename, data in file_data.items()
        if data['group'] == 'Services'
    ])

    views_children = '\n'.join([
        f"\t\t\t\t{data['file_ref_uuid']} /* {filename} */,"
        for filename, data in file_data.items()
        if data['group'] == 'Views'
    ])

    services_group = f"""\t\t{services_group_uuid} /* Services */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{services_children}
\t\t\t);
\t\t\tpath = Services;
\t\t\tsourceTree = "<group>";
\t\t}};
"""

    views_group = f"""\t\t{views_group_uuid} /* Views */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{views_children}
\t\t\t);
\t\t\tpath = Views;
\t\t\tsourceTree = "<group>";
\t\t}};
"""

    content = content[:group_section_end] + services_group + views_group + content[group_section_end:]

    # 5. Add files to PBXSourcesBuildPhase
    sources_phase_pattern = r'(isa = PBXSourcesBuildPhase;[^}]+files = \([^)]+)(A1B2C3D4E5F60718293A4B9B /\* CloudKitManager.swift in Sources \*/,)'
    match = re.search(sources_phase_pattern, content, re.DOTALL)
    if match:
        before = match.group(1)
        cloudkit_line = match.group(2)
        after = content[match.end():]

        # Add new source files
        new_sources = '\n'.join([
            f"\t\t\t\t{data['build_file_uuid']} /* {filename} in Sources */,"
            for filename, data in file_data.items()
        ])

        content = content[:match.start()] + before + new_sources + '\n\t\t\t\t' + cloudkit_line + after

    # Write modified content
    with open(PROJECT_FILE, 'w') as f:
        f.write(content)

    print("✅ Successfully added files to Xcode project:")
    for filename, data in file_data.items():
        print(f"  - {data['group']}/{filename}")

if __name__ == '__main__':
    main()
