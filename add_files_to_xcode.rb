#!/usr/bin/env ruby

# Simple script to add new Swift files to Xcode project
# This reads project.pbxproj and adds file references

require 'securerandom'

PROJECT_FILE = 'FamilyTodo.xcodeproj/project.pbxproj'

# Files to add
NEW_FILES = {
  'Services' => [
    'AuthenticationService.swift',
    'UserSession.swift'
  ],
  'Views' => [
    'SignInView.swift'
  ]
}

def generate_uuid
  SecureRandom.uuid.delete('-').upcase[0..23]
end

def add_files_to_project
  content = File.read(PROJECT_FILE)

  # Generate UUIDs for new files
  file_refs = {}
  build_files = {}

  NEW_FILES.each do |group, files|
    files.each do |file|
      file_ref_uuid = generate_uuid
      build_file_uuid = generate_uuid

      file_refs[file] = {
        uuid: file_ref_uuid,
        group: group,
        path: "#{group}/#{file}"
      }

      build_files[file] = {
        uuid: build_file_uuid,
        file_ref_uuid: file_ref_uuid
      }
    end
  end

  # Find PBXFileReference section
  file_ref_section_start = content.index('/* Begin PBXFileReference section */')
  file_ref_section_end = content.index('/* End PBXFileReference section */', file_ref_section_start)

  # Find PBXBuildFile section
  build_file_section_start = content.index('/* Begin PBXBuildFile section */')
  build_file_section_end = content.index('/* End PBXBuildFile section */', build_file_section_start)

  # Find PBXGroup section for FamilyTodo
  group_section = content[content.index('/* FamilyTodo */ = {')..content.index('/* End PBXGroup section */')]

  # Find PBXSourcesBuildPhase section
  sources_section_start = content.index('/* Begin PBXSourcesBuildPhase section */')
  sources_section_end = content.index('/* End PBXSourcesBuildPhase section */', sources_section_start)
  sources_section = content[sources_section_start..sources_section_end]

  # Find the files = ( array in sources build phase
  files_array_start = sources_section.index('files = (')
  files_array_end = sources_section.index(');', files_array_start)

  # Build new entries
  new_file_refs = []
  new_build_files = []
  new_source_refs = []

  file_refs.each do |file, info|
    # PBXFileReference entry
    new_file_refs << "\t\t#{info[:uuid]} /* #{file} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = #{file}; sourceTree = \"<group>\"; };"

    # PBXBuildFile entry
    build_uuid = build_files[file][:uuid]
    new_build_files << "\t\t#{build_uuid} /* #{file} in Sources */ = {isa = PBXBuildFile; fileRef = #{info[:uuid]} /* #{file} */; };"

    # Source build phase reference
    new_source_refs << "\t\t\t\t#{build_uuid} /* #{file} in Sources */,"
  end

  # Insert new PBXFileReference entries (before /* End PBXFileReference section */)
  insert_pos = file_ref_section_end
  new_file_refs.each do |entry|
    content.insert(insert_pos, "#{entry}\n")
    insert_pos += entry.length + 1
  end

  # Insert new PBXBuildFile entries (before /* End PBXBuildFile section */)
  insert_pos = content.index('/* End PBXBuildFile section */')
  new_build_files.each do |entry|
    content.insert(insert_pos, "#{entry}\n")
    insert_pos += entry.length + 1
  end

  # Insert new source references into build phase
  sources_files_end = content.index(');', content.index('/* Begin PBXSourcesBuildPhase section */'))
  new_source_refs.each do |entry|
    content.insert(sources_files_end, "#{entry}\n")
    sources_files_end += entry.length + 1
  end

  # We also need to add group references for Services and Views folders
  # Find the FamilyTodo group children array
  familytodo_group_start = content.index('A1B2C3D4E5F60718293A4B5A /* FamilyTodo */ = {')
  familytodo_children_start = content.index('children = (', familytodo_group_start)
  familytodo_children_end = content.index(');', familytodo_children_start)

  # Create group UUIDs
  services_group_uuid = generate_uuid
  views_group_uuid = generate_uuid

  # Add Services and Views group references to FamilyTodo children
  insert_pos = familytodo_children_end
  content.insert(insert_pos, "\t\t\t\t#{services_group_uuid} /* Services */,\n")
  insert_pos += "\t\t\t\t#{services_group_uuid} /* Services */,\n".length
  content.insert(insert_pos, "\t\t\t\t#{views_group_uuid} /* Views */,\n")

  # Add Services and Views PBXGroup definitions before /* End PBXGroup section */
  groups_section_end = content.index('/* End PBXGroup section */')

  services_children = file_refs.select { |f, i| i[:group] == 'Services' }.map { |f, i| "\t\t\t\t#{i[:uuid]} /* #{f} */," }.join("\n")
  views_children = file_refs.select { |f, i| i[:group] == 'Views' }.map { |f, i| "\t\t\t\t#{i[:uuid]} /* #{f} */," }.join("\n")

  services_group = <<~GROUP
  \t\t#{services_group_uuid} /* Services */ = {
  \t\t\tisa = PBXGroup;
  \t\t\tchildren = (
  #{services_children}
  \t\t\t);
  \t\t\tpath = Services;
  \t\t\tsourceTree = "<group>";
  \t\t};
  GROUP

  views_group = <<~GROUP
  \t\t#{views_group_uuid} /* Views */ = {
  \t\t\tisa = PBXGroup;
  \t\t\tchildren = (
  #{views_children}
  \t\t\t);
  \t\t\tpath = Views;
  \t\t\tsourceTree = "<group>";
  \t\t};
  GROUP

  content.insert(groups_section_end, services_group)
  content.insert(groups_section_end + services_group.length, views_group)

  # Write modified content
  File.write(PROJECT_FILE, content)

  puts "✅ Successfully added #{file_refs.size} files to Xcode project"
  puts "\nAdded files:"
  file_refs.each do |file, info|
    puts "  - #{info[:path]}"
  end
end

begin
  add_files_to_project
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace
  exit 1
end
