#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project. Python 3 standard library only."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1]
objects={}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def ref(name): return uid(name)
def add(key,isa,**fields):
    objects[uid(key)]={'isa':isa,**fields};return uid(key)
def q(s):return json.dumps(str(s))
def render(value):
    if isinstance(value,dict):return '{ '+ ' '.join(f'{q(k)} = {render(v)};' for k,v in value.items())+' }'
    if isinstance(value,list):return '( '+', '.join(render(v) for v in value)+' )'
    return q(value)
app_sources=sorted((ROOT/'SOULScan').glob('*.swift'))+[ROOT/'Core/SoulCore.cpp']
test_sources=[ROOT/'Tests/ExportTests.swift']
resources=[ROOT/'SOULScan/Assets.xcassets',ROOT/'SOULScan/PrivacyInfo.xcprivacy']
headers=[ROOT/'Core/SoulCore.h',ROOT/'SOULScan/Bridge.h',ROOT/'SOULScan/Info.plist']
source_refs=[];app_build=[];test_build=[];res_build=[]
for path in app_sources+test_sources+resources+headers:
    name=str(path.relative_to(ROOT));types={'.swift':'sourcecode.swift','.cpp':'sourcecode.cpp.cpp','.h':'sourcecode.c.h','.plist':'text.plist.xml','.xcprivacy':'text.xml','.xcassets':'folder.assetcatalog'}
    file=add(name,'PBXFileReference',lastKnownFileType=types.get(path.suffix,'text'),path=name,sourceTree='SOURCE_ROOT');source_refs.append(file)
    if path in app_sources or path in test_sources or path in resources:
        build=add('build:'+name,'PBXBuildFile',fileRef=file)
        (app_build if path in app_sources else test_build if path in test_sources else res_build).append(build)
app_product=add('app-product','PBXFileReference',explicitFileType='wrapper.application',includeInIndex='0',path='SOULScan.app',sourceTree='BUILT_PRODUCTS_DIR')
test_product=add('test-product','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex='0',path='SOULScanTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
products=add('products','PBXGroup',children=[app_product,test_product],name='Products',sourceTree='<group>')
group=add('main-group','PBXGroup',children=source_refs+[products],sourceTree='<group>')
for target,source,resource in [('app',app_build,res_build),('test',test_build,[])]:
    add(target+'-sources','PBXSourcesBuildPhase',buildActionMask='2147483647',files=source,runOnlyForDeploymentPostprocessing='0')
    add(target+'-resources','PBXResourcesBuildPhase',buildActionMask='2147483647',files=resource,runOnlyForDeploymentPostprocessing='0')
    add(target+'-frameworks','PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0')
common={'CLANG_CXX_LANGUAGE_STANDARD':'c++17','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0','SWIFT_STRICT_CONCURRENCY':'minimal','GCC_C_LANGUAGE_STANDARD':'gnu17','ENABLE_USER_SCRIPT_SANDBOXING':'YES'}
for config in ['Debug','Release']:
    settings=common|({'GCC_OPTIMIZATION_LEVEL':'0','SWIFT_OPTIMIZATION_LEVEL':'-Onone','DEBUG_INFORMATION_FORMAT':'dwarf','ENABLE_TESTABILITY':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG $(inherited)'} if config=='Debug' else {'GCC_OPTIMIZATION_LEVEL':'s','SWIFT_OPTIMIZATION_LEVEL':'-O','DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym','SWIFT_COMPILATION_MODE':'wholemodule'})
    add('project-'+config,'XCBuildConfiguration',buildSettings=settings,name=config)
    app={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'com.soul.scan.prototype','INFOPLIST_FILE':'SOULScan/Info.plist','GENERATE_INFOPLIST_FILE':'NO','TARGETED_DEVICE_FAMILY':'1','CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':'','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','SWIFT_OBJC_BRIDGING_HEADER':'SOULScan/Bridge.h','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'],'OTHER_LDFLAGS':['$(inherited)','-lc++'],'CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'0.1.0'}
    add('app-'+config,'XCBuildConfiguration',buildSettings=app,name=config)
    test={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'com.soul.scan.prototype.tests','GENERATE_INFOPLIST_FILE':'YES','TARGETED_DEVICE_FAMILY':'1','CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':'','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SWIFT_OBJC_BRIDGING_HEADER':'SOULScan/Bridge.h','BUNDLE_LOADER':'$(TEST_HOST)','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/SOULScan.app/SOULScan','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks','@loader_path/Frameworks']}
    add('test-'+config,'XCBuildConfiguration',buildSettings=test,name=config)
for name in ['project','app','test']: add(name+'-configs','XCConfigurationList',buildConfigurations=[ref(name+'-Debug'),ref(name+'-Release')],defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
proxy=add('test-proxy','PBXContainerItemProxy',containerPortal=ref('project'),proxyType='1',remoteGlobalIDString=ref('app-target'),remoteInfo='SOULScan')
dep=add('test-dependency','PBXTargetDependency',target=ref('app-target'),targetProxy=proxy)
add('app-target','PBXNativeTarget',buildConfigurationList=ref('app-configs'),buildPhases=[ref('app-sources'),ref('app-frameworks'),ref('app-resources')],buildRules=[],dependencies=[],name='SOULScan',productName='SOULScan',productReference=app_product,productType='com.apple.product-type.application')
add('test-target','PBXNativeTarget',buildConfigurationList=ref('test-configs'),buildPhases=[ref('test-sources'),ref('test-frameworks'),ref('test-resources')],buildRules=[],dependencies=[dep],name='SOULScanTests',productName='SOULScanTests',productReference=test_product,productType='com.apple.product-type.bundle.unit-test')
add('project','PBXProject',attributes={'LastUpgradeCheck':'1600','TargetAttributes':{ref('app-target'):{'CreatedOnToolsVersion':'16.0'},ref('test-target'):{'CreatedOnToolsVersion':'16.0','TestTargetID':ref('app-target')}}},buildConfigurationList=ref('project-configs'),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings='0',knownRegions=['en','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[ref('app-target'),ref('test-target')])
project=ROOT/'SOULScan.xcodeproj';project.mkdir(exist_ok=True)
text='// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'
text+='\n'.join(f'{key} = {render(value)};' for key,value in objects.items())
text+='\n}; rootObject = '+ref('project')+'; }\n';(project/'project.pbxproj').write_text(text)
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('app-target')}" BuildableName="SOULScan.app" BlueprintName="SOULScan" ReferencedContainer="container:SOULScan.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('test-target')}" BuildableName="SOULScanTests.xctest" BlueprintName="SOULScanTests" ReferencedContainer="container:SOULScan.xcodeproj"/></TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('app-target')}" BuildableName="SOULScan.app" BlueprintName="SOULScan" ReferencedContainer="container:SOULScan.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('app-target')}" BuildableName="SOULScan.app" BlueprintName="SOULScan" ReferencedContainer="container:SOULScan.xcodeproj"/></BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
schemes=project/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True);(schemes/'SOULScan.xcscheme').write_text(scheme)
print('Generated SOULScan.xcodeproj with app and XCTest targets.')
