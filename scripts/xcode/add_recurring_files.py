#!/usr/bin/env python3
"""Add recurring chores files to Xcode project."""

import re
import uuid
from pathlib import Path

def find_repo_root(start: Path) -> Path:
    cur = start
    while True:
        if (cur / "FamilyTodo.xcodeproj").is_dir():
            return cur
        if cur.parent == cur:
            raise FileNotFoundError("Could not locate repo root containing FamilyTodo.xcodeproj")
        cur = cur.parent


PROJECT_FILE = (
    find_repo_root(Path(__file__).resolve().parent)
    / "FamilyTodo.xcodeproj"
    / "project.pbxproj"
)

def generate_xcode_uuid():
    return uuid.uuid4().hex[:24].upper()

def main():
    with open(PROJECT_FILE, 'r') as f:
        content = f.read()

    files = {
        'RecurringChoreStore.swift': {'group': 'Stores'},
        'RecurringChoresView.swift': {'group': 'Views'},
    }

    for filename, data in files.items():
        data['file_ref'] = generate_xcode_uuid()
        data['build_file'] = generate_xcode_uuid()

    # 1. PBXBuildFile
    build_end = content.find('/* End PBXBuildFile section */')
    entries = ''
    for filename, data in files.items():
        entries += f"\t\t{data['build_file']} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {data['file_ref']} /* {filename} */; }};\n"
    content = content[:build_end] + entries + content[build_end:]

    # 2. PBXFileReference
    ref_end = content.find('/* End PBXFileReference section */')
    entries = ''
    for filename, data in files.items():
        entries += f"\t\t{data['file_ref']} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};\n"
    content = content[:ref_end] + entries + content[ref_end:]

    # 3. Add to groups
    stores_uuid = re.search(r'(\w+) /\* Stores \*/ = \{', content).group(1)
    views_uuid = re.search(r'(\w+) /\* Views \*/ = \{', content).group(1)

    pattern = rf'({stores_uuid} /\* Stores \*/ = \{{\s*isa = PBXGroup;\s*children = \()'
    match = re.search(pattern, content)
    if match:
        ref = files['RecurringChoreStore.swift']['file_ref']
        content = content[:match.end()] + f"\n\t\t\t\t{ref} /* RecurringChoreStore.swift */," + content[match.end():]

    pattern = rf'({views_uuid} /\* Views \*/ = \{{\s*isa = PBXGroup;\s*children = \()'
    match = re.search(pattern, content)
    if match:
        ref = files['RecurringChoresView.swift']['file_ref']
        content = content[:match.end()] + f"\n\t\t\t\t{ref} /* RecurringChoresView.swift */," + content[match.end():]

    # 4. PBXSourcesBuildPhase
    pattern = r'(isa = PBXSourcesBuildPhase;[^}]+files = \()'
    match = re.search(pattern, content)
    if match:
        entries = ''
        for filename, data in files.items():
            entries += f"\n\t\t\t\t{data['build_file']} /* {filename} in Sources */,"
        content = content[:match.end()] + entries + content[match.end():]

    with open(PROJECT_FILE, 'w') as f:
        f.write(content)

    print("✅ Added recurring chores files")

if __name__ == '__main__':
    main()
