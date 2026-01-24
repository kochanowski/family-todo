#!/bin/bash
# Script to add FamilyTodoUITests target to Xcode project

set -e

PROJECT_FILE="FamilyTodo.xcodeproj/project.pbxproj"

# Fixed UUIDs for UI test target
UITEST_TARGET="UITEST00000000000000001"
UITEST_FILE_REF="UITEST00000000000000002"
UITEST_BUILD_FILE="UITEST00000000000000003"
UITEST_GROUP="UITEST00000000000000004"
UITEST_SOURCES_PHASE="UITEST00000000000000005"
UITEST_FRAMEWORKS_PHASE="UITEST00000000000000006"
UITEST_RESOURCES_PHASE="UITEST00000000000000007"
UITEST_DEBUG_CONFIG="UITEST00000000000000008"
UITEST_RELEASE_CONFIG="UITEST00000000000000009"
UITEST_CONFIG_LIST="UITEST0000000000000000A"
UITEST_PROXY="UITEST0000000000000000B"
UITEST_DEPENDENCY="UITEST0000000000000000C"
UITEST_PRODUCT="UITEST0000000000000000D"

cp "$PROJECT_FILE" "$PROJECT_FILE.backup"

# 1. Add PBXBuildFile entry for UI test file
sed -i "/\/\* End PBXBuildFile section \*\//i\\
\\t\\t${UITEST_BUILD_FILE} \/\* FamilyTodoUITests.swift in Sources \*\/ = {isa = PBXBuildFile; fileRef = ${UITEST_FILE_REF} \/\* FamilyTodoUITests.swift \*\/; };" "$PROJECT_FILE"

# 2. Add PBXContainerItemProxy for UI tests
sed -i "/\/\* End PBXContainerItemProxy section \*\//i\\
\\t\\t${UITEST_PROXY} \/\* PBXContainerItemProxy \*\/ = {\\
\\t\\t\\tisa = PBXContainerItemProxy;\\
\\t\\t\\tcontainerPortal = A1B2C3D4E5F60718293A4B5C \/\* Project object \*\/;\\
\\t\\t\\tproxyType = 1;\\
\\t\\t\\tremoteGlobalIDString = A1B2C3D4E5F60718293A4B60;\\
\\t\\t\\tremoteInfo = HousePulse;\\
\\t\\t};" "$PROJECT_FILE"

# 3. Add PBXFileReference for test file and product
sed -i "/\/\* End PBXFileReference section \*\//i\\
\\t\\t${UITEST_FILE_REF} \/\* FamilyTodoUITests.swift \*\/ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FamilyTodoUITests.swift; sourceTree = \"<group>\"; };\\
\\t\\t${UITEST_PRODUCT} \/\* FamilyTodoUITests.xctest \*\/ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = FamilyTodoUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };" "$PROJECT_FILE"

# 4. Add PBXGroup for UI tests
sed -i "/\/\* End PBXGroup section \*\//i\\
\\t\\t${UITEST_GROUP} \/\* FamilyTodoUITests \*\/ = {\\
\\t\\t\\tisa = PBXGroup;\\
\\t\\t\\tchildren = (\\
\\t\\t\\t\\t${UITEST_FILE_REF} \/\* FamilyTodoUITests.swift \*\/,\\
\\t\\t\\t);\\
\\t\\t\\tpath = FamilyTodoUITests;\\
\\t\\t\\tsourceTree = \"<group>\";\\
\\t\\t};" "$PROJECT_FILE"

# 5. Add UI test target to Products group - find the line and add after
sed -i "/A1B2C3D4E5F60718293A4B76 \/\* FamilyTodoTests.xctest \*\/,/a\\
\\t\\t\\t\\t${UITEST_PRODUCT} \/\* FamilyTodoUITests.xctest \*\/," "$PROJECT_FILE"

# 6. Add FamilyTodoUITests group to main group
sed -i "/A1B2C3D4E5F60718293A4B83 \/\* FamilyTodoTests \*\/,/a\\
\\t\\t\\t\\t${UITEST_GROUP} \/\* FamilyTodoUITests \*\/," "$PROJECT_FILE"

# 7. Add PBXNativeTarget for UI tests (before End PBXNativeTarget section)
sed -i "/\/\* End PBXNativeTarget section \*\//i\\
\\t\\t${UITEST_TARGET} \/\* FamilyTodoUITests \*\/ = {\\
\\t\\t\\tisa = PBXNativeTarget;\\
\\t\\t\\tbuildConfigurationList = ${UITEST_CONFIG_LIST} \/\* Build configuration list for PBXNativeTarget \"FamilyTodoUITests\" \*\/;\\
\\t\\t\\tbuildPhases = (\\
\\t\\t\\t\\t${UITEST_SOURCES_PHASE} \/\* Sources \*\/,\\
\\t\\t\\t\\t${UITEST_FRAMEWORKS_PHASE} \/\* Frameworks \*\/,\\
\\t\\t\\t\\t${UITEST_RESOURCES_PHASE} \/\* Resources \*\/,\\
\\t\\t\\t);\\
\\t\\t\\tbuildRules = (\\
\\t\\t\\t);\\
\\t\\t\\tdependencies = (\\
\\t\\t\\t\\t${UITEST_DEPENDENCY} \/\* PBXTargetDependency \*\/,\\
\\t\\t\\t);\\
\\t\\t\\tname = FamilyTodoUITests;\\
\\t\\t\\tproductName = FamilyTodoUITests;\\
\\t\\t\\tproductReference = ${UITEST_PRODUCT} \/\* FamilyTodoUITests.xctest \*\/;\\
\\t\\t\\tproductType = \"com.apple.product-type.bundle.ui-testing\";\\
\\t\\t};" "$PROJECT_FILE"

# 8. Add build phases
sed -i "/\/\* End PBXResourcesBuildPhase section \*\//i\\
\\t\\t${UITEST_RESOURCES_PHASE} \/\* Resources \*\/ = {\\
\\t\\t\\tisa = PBXResourcesBuildPhase;\\
\\t\\t\\tbuildActionMask = 2147483647;\\
\\t\\t\\tfiles = (\\
\\t\\t\\t);\\
\\t\\t\\trunOnlyForDeploymentPostprocessing = 0;\\
\\t\\t};" "$PROJECT_FILE"

sed -i "/\/\* End PBXSourcesBuildPhase section \*\//i\\
\\t\\t${UITEST_SOURCES_PHASE} \/\* Sources \*\/ = {\\
\\t\\t\\tisa = PBXSourcesBuildPhase;\\
\\t\\t\\tbuildActionMask = 2147483647;\\
\\t\\t\\tfiles = (\\
\\t\\t\\t\\t${UITEST_BUILD_FILE} \/\* FamilyTodoUITests.swift in Sources \*\/,\\
\\t\\t\\t);\\
\\t\\t\\trunOnlyForDeploymentPostprocessing = 0;\\
\\t\\t};" "$PROJECT_FILE"

sed -i "/\/\* End PBXFrameworksBuildPhase section \*\//i\\
\\t\\t${UITEST_FRAMEWORKS_PHASE} \/\* Frameworks \*\/ = {\\
\\t\\t\\tisa = PBXFrameworksBuildPhase;\\
\\t\\t\\tbuildActionMask = 2147483647;\\
\\t\\t\\tfiles = (\\
\\t\\t\\t);\\
\\t\\t\\trunOnlyForDeploymentPostprocessing = 0;\\
\\t\\t};" "$PROJECT_FILE"

# 9. Add PBXTargetDependency
sed -i "/\/\* End PBXTargetDependency section \*\//i\\
\\t\\t${UITEST_DEPENDENCY} \/\* PBXTargetDependency \*\/ = {\\
\\t\\t\\tisa = PBXTargetDependency;\\
\\t\\t\\ttarget = A1B2C3D4E5F60718293A4B60 \/\* HousePulse \*\/;\\
\\t\\t\\ttargetProxy = ${UITEST_PROXY} \/\* PBXContainerItemProxy \*\/;\\
\\t\\t};" "$PROJECT_FILE"

# 10. Add build configurations
sed -i "/\/\* End XCBuildConfiguration section \*\//i\\
\\t\\t${UITEST_DEBUG_CONFIG} \/\* Debug \*\/ = {\\
\\t\\t\\tisa = XCBuildConfiguration;\\
\\t\\t\\tbuildSettings = {\\
\\t\\t\\t\\tCLANG_ENABLE_MODULES = YES;\\
\\t\\t\\t\\tCODE_SIGN_STYLE = Automatic;\\
\\t\\t\\t\\tDEVELOPMENT_TEAM = \"\";\\
\\t\\t\\t\\tGENERATE_INFOPLIST_FILE = YES;\\
\\t\\t\\t\\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\\
\\t\\t\\t\\tPRODUCT_BUNDLE_IDENTIFIER = com.example.familytodo.uitests;\\
\\t\\t\\t\\tPRODUCT_NAME = \"\$(TARGET_NAME)\";\\
\\t\\t\\t\\tSDKROOT = iphoneos;\\
\\t\\t\\t\\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";\\
\\t\\t\\t\\tSWIFT_VERSION = 5.9;\\
\\t\\t\\t\\tTARGETED_DEVICE_FAMILY = 1;\\
\\t\\t\\t\\tTEST_TARGET_NAME = HousePulse;\\
\\t\\t\\t};\\
\\t\\t\\tname = Debug;\\
\\t\\t};\\
\\t\\t${UITEST_RELEASE_CONFIG} \/\* Release \*\/ = {\\
\\t\\t\\tisa = XCBuildConfiguration;\\
\\t\\t\\tbuildSettings = {\\
\\t\\t\\t\\tCLANG_ENABLE_MODULES = YES;\\
\\t\\t\\t\\tCODE_SIGN_STYLE = Automatic;\\
\\t\\t\\t\\tDEVELOPMENT_TEAM = \"\";\\
\\t\\t\\t\\tGENERATE_INFOPLIST_FILE = YES;\\
\\t\\t\\t\\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\\
\\t\\t\\t\\tPRODUCT_BUNDLE_IDENTIFIER = com.example.familytodo.uitests;\\
\\t\\t\\t\\tPRODUCT_NAME = \"\$(TARGET_NAME)\";\\
\\t\\t\\t\\tSDKROOT = iphoneos;\\
\\t\\t\\t\\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";\\
\\t\\t\\t\\tSWIFT_COMPILATION_MODE = wholemodule;\\
\\t\\t\\t\\tSWIFT_VERSION = 5.9;\\
\\t\\t\\t\\tTARGETED_DEVICE_FAMILY = 1;\\
\\t\\t\\t\\tTEST_TARGET_NAME = HousePulse;\\
\\t\\t\\t};\\
\\t\\t\\tname = Release;\\
\\t\\t};" "$PROJECT_FILE"

# 11. Add configuration list
sed -i "/\/\* End XCConfigurationList section \*\//i\\
\\t\\t${UITEST_CONFIG_LIST} \/\* Build configuration list for PBXNativeTarget \"FamilyTodoUITests\" \*\/ = {\\
\\t\\t\\tisa = XCConfigurationList;\\
\\t\\t\\tbuildConfigurations = (\\
\\t\\t\\t\\t${UITEST_DEBUG_CONFIG} \/\* Debug \*\/,\\
\\t\\t\\t\\t${UITEST_RELEASE_CONFIG} \/\* Release \*\/,\\
\\t\\t\\t);\\
\\t\\t\\tdefaultConfigurationIsVisible = 0;\\
\\t\\t\\tdefaultConfigurationName = Release;\\
\\t\\t};" "$PROJECT_FILE"

# 12. Add target to project targets list
sed -i "s/A1B2C3D4E5F60718293A4B61 \/\* FamilyTodoTests \*\/,/A1B2C3D4E5F60718293A4B61 \/\* FamilyTodoTests \*\/,\\
\\t\\t\\t\\t${UITEST_TARGET} \/\* FamilyTodoUITests \*\/,/" "$PROJECT_FILE"

rm -f "$PROJECT_FILE.backup"

echo "✓ Added FamilyTodoUITests target to project"
