#!/usr/bin/env python3
"""Deterministic, dependency-free Xcode project generation. Not needed to build."""
import hashlib,json,plistlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def uid(s):return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def q(s):return json.dumps(s)
objects=[]
def add(key, body):objects.append(f'\t\t{uid(key)} = {{ {body} }};')
def ids(values):return '( '+', '.join(uid(x) for x in values)+' )'
sources=sorted(p.relative_to(ROOT).as_posix() for p in (ROOT/'Sources').rglob('*.swift'))
resources=['Resources/Assets.xcassets','Resources/Engine','Resources/EngineSetup.command']
for path in sources+resources:
    kind='sourcecode.swift' if path.endswith('.swift') else 'folder.assetcatalog' if path.endswith('xcassets') else 'folder' if path.endswith('/Engine') else 'text.script.sh'
    add('file:'+path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {q(path)}; sourceTree = SOURCE_ROOT;')
    add('build:'+path, f'isa = PBXBuildFile; fileRef = {uid("file:"+path)};')
add('app','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Dissect.app; sourceTree = BUILT_PRODUCTS_DIR;')
add('group-source',f'isa = PBXGroup; children = {ids(["file:"+p for p in sources])}; name = Sources; sourceTree = "<group>";')
add('group-resources',f'isa = PBXGroup; children = {ids(["file:"+p for p in resources])}; name = Resources; sourceTree = "<group>";')
add('products',f'isa = PBXGroup; children = {ids(["app"])}; name = Products; sourceTree = "<group>";')
add('group',f'isa = PBXGroup; children = {ids(["group-source","group-resources","products"])}; sourceTree = "<group>";')
for key,isa,files in [('sources','PBXSourcesBuildPhase',sources),('resources','PBXResourcesBuildPhase',resources),('frameworks','PBXFrameworksBuildPhase',[])]:
    add(key,f'isa = {isa}; buildActionMask = 2147483647; files = {ids(["build:"+p for p in files])}; runOnlyForDeploymentPostprocessing = 0;')
add('target',f'isa = PBXNativeTarget; buildConfigurationList = {uid("target-configs")}; buildPhases = {ids(["sources","frameworks","resources"])}; buildRules = (); dependencies = (); name = Dissect; productName = Dissect; productReference = {uid("app")}; productType = "com.apple.product-type.application";')
for mode in ['Debug','Release']:
    project_settings='CLANG_ENABLE_MODULES = YES; MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 5.0;'
    if mode=='Debug':project_settings+=' DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;'
    else:project_settings+=' DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; SWIFT_COMPILATION_MODE = wholemodule; SWIFT_OPTIMIZATION_LEVEL = "-O";'
    add('project-'+mode,f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {project_settings} }};')
    target_settings='ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor; CODE_SIGN_STYLE = Automatic; COMBINE_HIDPI_IMAGES = YES; CURRENT_PROJECT_VERSION = 2; ENABLE_APP_SANDBOX = NO; ENABLE_HARDENED_RUNTIME = YES; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = Resources/Info.plist; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks"; MARKETING_VERSION = 0.1.1; PRODUCT_BUNDLE_IDENTIFIER = com.greenshoegarage.dissect; PRODUCT_NAME = "$(TARGET_NAME)"; SWIFT_EMIT_LOC_STRINGS = YES;'
    add('target-'+mode,f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {target_settings} }};')
for scope in ['project','target']:
    add(scope+'-configs',f'isa = XCConfigurationList; buildConfigurations = {ids([scope+"-Debug",scope+"-Release"])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 1500; LastUpgradeCheck = 1500; }}; buildConfigurationList = {uid("project-configs")}; compatibilityVersion = "Xcode 15.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = {uid("group")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = {ids(["target"])};')
(ROOT/'Dissect.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 60; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = '+uid('project')+'; }\n')
reference=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target")}" BuildableName="Dissect.app" BlueprintName="Dissect" ReferencedContainer="container:Dissect.xcodeproj"/>'
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(ROOT/'Dissect.xcodeproj/xcshareddata/xcschemes/Dissect.xcscheme').write_text(scheme)
info=dict(CFBundleDevelopmentRegion='en',CFBundleDisplayName='Dissect',CFBundleExecutable='$(EXECUTABLE_NAME)',CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',CFBundleInfoDictionaryVersion='6.0',CFBundleName='Dissect',CFBundlePackageType='APPL',CFBundleShortVersionString='$(MARKETING_VERSION)',CFBundleVersion='$(CURRENT_PROJECT_VERSION)',LSMinimumSystemVersion='$(MACOSX_DEPLOYMENT_TARGET)',NSHighResolutionCapable=True,NSPrincipalClass='NSApplication',NSHumanReadableCopyright='Copyright © 2026 Green Shoe Garage. Independent software powered by Ghidra.',CFBundleIconName='AppIcon',CFBundleDocumentTypes=[dict(CFBundleTypeName='Dissect Workspace',CFBundleTypeRole='Editor',LSHandlerRank='Owner',LSItemContentTypes=['com.greenshoegarage.dissect.workspace'])],UTExportedTypeDeclarations=[dict(UTTypeIdentifier='com.greenshoegarage.dissect.workspace',UTTypeDescription='Dissect Workspace',UTTypeConformsTo=['com.apple.package'],UTTypeTagSpecification={'public.filename-extension':['dissect']})])
with (ROOT/'Resources/Info.plist').open('wb') as f:plistlib.dump(info,f)
print('Generated project and scheme for',len(sources),'Swift sources.')
