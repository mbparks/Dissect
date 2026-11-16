#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:?Usage: check-app-launch.sh /path/to/Dissect.app}"
mkdir -p build/evidence
report="$PWD/build/evidence/app-launch.json"
test ! -e "$report"
open -n "$app" --args --smoke-test "$report"
for ((attempt=0; attempt<180; attempt++)); do
  if [ -f "$report" ]; then break; fi
  sleep 1
done
if [ ! -f "$report" ]; then
  echo 'App failed to finish launch check within three minutes.' >&2
  ls -lt "$HOME/Library/Logs/DiagnosticReports" | head -12 || true
  exit 1
fi
cat "$report"
python3 - "$report" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['success']
PY
sleep 2
screencapture -x build/evidence/dissect-running.png || true
osascript -e 'tell application "Dissect" to quit'
python3 scripts/bundle-integrity.py "$app" build/evidence/bundle-before.json | tee build/evidence/bundle-after-app.json
codesign --verify --deep --strict --verbose=4 "$app"
