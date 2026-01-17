#!/usr/bin/env python3
import re
import uuid

PROJECT_FILE = 'FamilyTodo.xcodeproj/project.pbxproj'

def generate_xcode_uuid():
    return uuid.uuid4().hex[:24].upper()

def main():
    with open(PROJECT_FILE, 'r') as f:
        content = f.read()

    file_ref = generate_xcode_uuid()
    build_file = generate_xcode_uuid()
    filename = 'NotificationService.swift'

    # 1. PBXBuildFile
    build_end = content.find('/* End PBXBuildFile section */')
    entry = f"\t\t{build_file} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* {filename} */; }};\n"
    content = content[:build_end] + entry + content[build_end:]

    # 2. PBXFileReference
    ref_end = content.find('/* End PBXFileReference section */')
    entry = f"\t\t{file_ref} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};\n"
    content = content[:ref_end] + entry + content[ref_end:]

    # 3. Add to Services group
    services_uuid = re.search(r'(\w+) /\* Services \*/ = \{', content).group(1)
    pattern = rf'({services_uuid} /\* Services \*/ = \{{\s*isa = PBXGroup;\s*children = \()'
    match = re.search(pattern, content)
    if match:
        content = content[:match.end()] + f"\n\t\t\t\t{file_ref} /* {filename} */," + content[match.end():]

    # 4. PBXSourcesBuildPhase
    pattern = r'(isa = PBXSourcesBuildPhase;[^}]+files = \()'
    match = re.search(pattern, content)
    if match:
        content = content[:match.end()] + f"\n\t\t\t\t{build_file} /* {filename} in Sources */," + content[match.end():]

    with open(PROJECT_FILE, 'w') as f:
        f.write(content)

    print("✅ Added NotificationService.swift")

if __name__ == '__main__':
    main()
