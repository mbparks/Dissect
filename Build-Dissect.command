#!/bin/bash
cd "$(dirname "$0")" || exit 1
bash scripts/build-macos.sh Dissect.xcodeproj Dissect Dissect
result=$?
if [ "$result" -ne 0 ]; then echo "Build failed. Keep the printed build.log for troubleshooting."; fi
if [ -t 0 ]; then read -r -p "Press Return to close."; fi
exit "$result"
