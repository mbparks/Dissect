#!/usr/bin/env python3
"""Sign nested Mach-O code inside-out; never use codesign --deep for signing."""
import pathlib, subprocess, sys
app=pathlib.Path(sys.argv[1]).resolve()
magic={b'\xfe\xed\xfa\xce',b'\xce\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xca\xfe\xba\xbf',b'\xbf\xba\xfe\xca'}
count=0
for path in sorted(app.rglob('*'),key=lambda p:len(p.parts),reverse=True):
    if path.is_symlink() or not path.is_file(): continue
    with path.open('rb') as stream: header=stream.read(4)
    kind = subprocess.check_output(['file','-b',str(path)],text=True) if header in magic else ''
    if 'Mach-O' in kind and 'object' not in kind:
        subprocess.run(['codesign','--force','--sign','-',str(path)],check=True)
        count+=1
java=app/'Contents/Resources/Runtime/java.jdk'
if (java/'Contents/Info.plist').exists():
    subprocess.run(['codesign','--force','--sign','-',str(java)],check=True)
subprocess.run(['codesign','--force','--sign','-','--options','runtime',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict','--verbose=2',str(app)],check=True)
print(f'Signed {count} Mach-O objects and verified complete app. Ad-hoc; not notarized.')
