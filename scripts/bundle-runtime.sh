#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -s)" = Darwin
test "$(uname -m)" = arm64
destination="${1:?Usage: bundle-runtime.sh /path/to/Dissect.app}"
runtime="$destination/Contents/Resources/Runtime"
mkdir -p build/downloads "$runtime" "$destination/Contents/Resources/Samples" "$destination/Contents/Resources/Notices"
fetch() {
  local url="$1" target="$2" hash="$3"
  if [ ! -f "$target" ] || [ "$(shasum -a 256 "$target" | awk '{print $1}')" != "$hash" ]; then
    curl --fail --location --retry 3 --connect-timeout 30 --output "$target.part" "$url"
    mv "$target.part" "$target"
  fi
  echo "$hash  $target" | shasum -a 256 -c -
}
fetch 'https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.2_build/ghidra_12.2_PUBLIC_20261016.zip' build/downloads/ghidra.zip 2c2cd776db3c1f6a097ba418922378ac3649cadd5e844a6f5f088ae628a7be67
fetch 'https://github.com/astral-sh/python-build-standalone/releases/download/20261110/cpython-3.13.18%2B20261110-aarch64-apple-darwin-install_only_stripped.tar.gz' build/downloads/python.tar.gz 7a2384641584ab9984221fcb0fc9265df465922af71be71410529e2a9c3f0540
fetch 'https://corretto.aws/downloads/resources/25.0.5.0.10/amazon-corretto-25.0.5.0.10-macosx-aarch64.tar.gz' build/downloads/java.tar.gz 0da6df8bf4f849939951089e1d10f9fea5df82a7da9f66434f6c2b31c497fe75
staging="$(mktemp -d "$PWD/build/runtime.XXXXXX")"
ditto -x -k build/downloads/ghidra.zip "$staging"
mv "$staging/ghidra_12.2_PUBLIC" "$runtime/ghidra"
tar -xzf build/downloads/python.tar.gz -C "$runtime"
tar -xzf build/downloads/java.tar.gz -C "$staging"
java_source="$(find "$staging" -type d -name '*.jdk' -print -quit)"
test -n "$java_source"
mv "$java_source" "$runtime/java.jdk"
export JAVA_HOME="$runtime/java.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
export PYTHONDONTWRITEBYTECODE=1 PYTHONNOUSERSITE=1
unset PYTHONHOME PYTHONPATH || true
python_bin="$runtime/python/bin/python3"
"$python_bin" -m pip install --no-index --no-compile --find-links "$runtime/ghidra/Ghidra/Features/PyGhidra/pypkg/dist" 'pyghidra==3.2.0' 'JPype1==1.5.2'
(
  cd "$runtime/ghidra/support/gradle"
  MACOSX_DEPLOYMENT_TARGET=14.0 ./gradlew --no-daemon buildNatives
)
# Support Gradle writes into each module's build/os directory. Install the
# resulting files into the distribution's normal os directory before cleanup.
"$python_bin" - "$runtime/ghidra" <<'PYINSTALL'
from pathlib import Path
import shutil,sys
root=Path(sys.argv[1])
for native in root.glob('**/build/os/mac_arm_64'):
    target=native.parents[2]/'os/mac_arm_64'
    shutil.copytree(native,target,dirs_exist_ok=True)
    print('Installed native module:',target)
PYINSTALL
decompiler="$runtime/ghidra/Ghidra/Features/Decompiler/os/mac_arm_64/decompile"
if [ ! -x "$decompiler" ]; then
  find "$runtime/ghidra" -name decompile -print
  echo 'Native decompiler install failed' >&2
  exit 1
fi
find "$runtime/ghidra" -type d \( -name build -o -name .gradle \) -prune -exec rm -rf {} +
test -x "$decompiler"
file "$decompiler" "$python_bin" "$JAVA_HOME/bin/java"
cp examples/firmware-arm64-macho.o "$destination/Contents/Resources/Samples/"
cp LICENSE THIRD-PARTY-NOTICES.md "$destination/Contents/Resources/Notices/"
find "$runtime" -type d -name __pycache__ -prune -exec rm -rf {} +
printf '%s\n' 'Ghidra 12.2 / PyGhidra 3.2.0 / JPype 1.5.2 / CPython 3.13.18 / Corretto 25.0.5.0.10' > "$destination/Contents/Resources/Notices/RUNTIME-VERSIONS.txt"
# Ghidra 12.2 creates .sla.lock files beside processor definitions when writable.
# A signed app contains immutable, precompiled languages. Ghidra's supported
# read-only-install path skips those locks and reads the existing .sla files.
chmod -R a-w "$runtime/ghidra/Ghidra/Processors"
