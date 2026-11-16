#!/usr/bin/env python3
"""Dependency-free static release consistency check; does not compile SwiftUI."""
import json,plistlib,re,stat,sys,xml.etree.ElementTree as ET
from pathlib import Path
root=Path(__file__).resolve().parents[1]
pbx=(root/'Dissect.xcodeproj/project.pbxproj').read_text()
paths=re.findall(r'path = "([^"]+)";',pbx)
for path in paths:
    assert (root/path).exists(),f'Missing project member: {path}'
for path in (root/'Sources').rglob('*.swift'):
    relative=path.relative_to(root).as_posix()
    assert paths.count(relative)==1,f'Incorrect source membership: {relative}'
assert len(re.findall('isa = PBXNativeTarget;',pbx))==1
ET.parse(root/'Dissect.xcodeproj/xcshareddata/xcschemes/Dissect.xcscheme')
info=plistlib.loads((root/'Resources/Info.plist').read_bytes())
assert info['CFBundleDocumentTypes'][0]['LSItemContentTypes']==['com.greenshoegarage.dissect.workspace']
assert 'MACOSX_DEPLOYMENT_TARGET = 14.0' in pbx
for asset in (root/'Resources/Assets.xcassets').glob('*/Contents.json'):
    data=json.loads(asset.read_text())
    for entry in data.get('images',[]):assert (asset.parent/entry['filename']).is_file()
for f in list(root.glob('*.command'))+[root/'Resources/EngineSetup.command']:
    assert f.stat().st_mode & stat.S_IXUSR, f'Missing executable bit: {f}'
assert (root/'Resources/Engine/engine.py').is_file() and (root/'Resources/Engine/storage.py').is_file()
source_count=len(list((root/'Sources').rglob('*.swift')))
print(f'Project paths, {source_count} Swift source memberships, scheme, plist, icon assets, deployment settings, and command permissions passed ({len(paths)} references).')
