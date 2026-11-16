#!/usr/bin/env python3
"""Record/diff the signed bundle to catch runtime writes before release."""
import hashlib,json,os,sys
from pathlib import Path
app=Path(sys.argv[1]); record=Path(sys.argv[2])
current={}
for p in sorted(app.rglob('*')):
    key=p.relative_to(app).as_posix()
    if p.is_symlink(): current[key]='symlink:'+os.readlink(p)
    elif p.is_file():
        with p.open('rb') as f: current[key]=hashlib.file_digest(f,'sha256').hexdigest()
if not record.exists():
    record.write_text(json.dumps(current,sort_keys=True)); print('Recorded signed bundle:',len(current),'files')
else:
    previous=json.loads(record.read_text())
    changes=[{'path':p,'change':'added' if p not in previous else 'removed' if p not in current else 'modified'} for p in sorted(set(previous)|set(current)) if previous.get(p)!=current.get(p)]
    print(json.dumps({'bundle_changes':changes},indent=2))
    sys.exit(bool(changes))
