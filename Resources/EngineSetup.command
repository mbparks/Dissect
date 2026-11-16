#!/bin/bash
# Installs dependencies inside this user's Application Support directory only.
set -euo pipefail
umask 077
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
  echo "This setup is for an Apple Silicon Mac running natively (not a Rosetta Terminal)."
  exit 1
fi
runtime_root="$HOME/Library/Application Support/Dissect"
mkdir -p "$runtime_root/logs"
log="$runtime_root/logs/setup-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$log") 2>&1
finish() {
  result="${1:-$?}"
  if [ "$result" -ne 0 ]; then echo "Setup stopped. No workspace data was changed. Log: $log"; fi
  if [ -t 0 ]; then read -r -p "Press Return to close." || true; fi
  exit "$result"
}
trap 'finish "$?"' EXIT
if ! xcrun --find clang >/dev/null 2>&1; then
  echo "Install Xcode Command Line Tools with: xcode-select --install"
  echo "Finish the installation, then run this script again."
  exit 1
fi
python_bin=""
for candidate in /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.11 /Library/Frameworks/Python.framework/Versions/3.13/bin/python3 /Library/Frameworks/Python.framework/Versions/3.12/bin/python3 /Library/Frameworks/Python.framework/Versions/3.11/bin/python3 "$(command -v python3 || true)"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" -c 'import platform,sys;sys.exit(not ((3,10)<=sys.version_info[:2]<=(3,13) and platform.machine()=="arm64"))' 2>/dev/null; then
    python_bin="$candidate"; break
  fi
done
if [ -z "$python_bin" ]; then
  echo "Install the universal2 Python 3.13 macOS installer from https://www.python.org/downloads/macos/"
  echo "Or, if you use Homebrew: brew install python@3.13"
  echo "Then run Set Up Engine again. Python 3.10–3.13 ARM64 is required by this pinned preview."
  exit 1
fi
# Avoid two setup processes changing the same native components/venv.
lock_dir="$runtime_root/setup.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "Another setup appears to be running. If it was interrupted, remove only $lock_dir and retry."
  exit 1
fi
trap 'result=$?; rmdir "$lock_dir" 2>/dev/null || true; finish "$result"' EXIT
cache="$runtime_root/downloads"
mkdir -p "$cache"
echo "Dissect Engine Setup — Ghidra 12.2 / Apple Silicon"
echo "Downloads about 800 MB; allow at least 3 GB free. No binaries you analyze are uploaded."
fetch() {
  local url="$1" target="$2"
  curl --fail --location --retry 3 --connect-timeout 30 --output "$target.part" "$url"
  mv "$target.part" "$target"
}
verify() {
  local file="$1" expected="$2" actual
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then echo "Checksum failed for $file"; return 1; fi
}
ghidra_home="$runtime_root/ghidra_12.2_PUBLIC"
if [ ! -f "$ghidra_home/Ghidra/application.properties" ]; then
  archive="$cache/ghidra_12.2_PUBLIC_20261016.zip"
  checksum=2c2cd776db3c1f6a097ba418922378ac3649cadd5e844a6f5f088ae628a7be67
  if [ ! -f "$archive" ] || ! verify "$archive" "$checksum"; then
    fetch https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.2_build/ghidra_12.2_PUBLIC_20261016.zip "$archive"
  fi
  verify "$archive" "$checksum"
  staging="$(mktemp -d "$runtime_root/unpack.XXXXXX")"
  ditto -x -k "$archive" "$staging"
  mv "$staging/ghidra_12.2_PUBLIC" "$ghidra_home"
  rmdir "$staging"
fi
java_home="$(/usr/libexec/java_home -v 25 -a arm64 2>/dev/null || true)"
if [ -z "$java_home" ]; then
  if [ -f "$runtime_root/java-home.txt" ]; then java_home="$(cat "$runtime_root/java-home.txt")"; fi
fi
if [ -n "$java_home" ] && [ -x "$java_home/bin/java" ]; then
  if ! "$python_bin" - "$java_home/bin/java" <<'PYJAVA'
import subprocess,sys
r=subprocess.run([sys.argv[1],'-XshowSettings:properties','-version'],capture_output=True,text=True)
sys.exit(not (r.returncode==0 and 'java.specification.version = 25' in r.stderr and 'os.arch = aarch64' in r.stderr))
PYJAVA
  then java_home=""; fi
fi
if [ -z "$java_home" ] || [ ! -x "$java_home/bin/java" ]; then
  java_archive="$cache/corretto-25-arm64.tar.gz"
  fetch https://corretto.aws/downloads/latest/amazon-corretto-25-aarch64-macos-jdk.tar.gz "$java_archive"
  checksum_file="$cache/corretto-25.sha256"
  fetch https://corretto.aws/downloads/latest_sha256/amazon-corretto-25-aarch64-macos-jdk.tar.gz "$checksum_file"
  java_checksum="$(awk '{print $1}' "$checksum_file")"
  if ! [[ "$java_checksum" =~ ^[0-9a-fA-F]{64}$ ]]; then echo "Invalid vendor checksum response"; exit 1; fi
  verify "$java_archive" "$java_checksum"
  staging="$(mktemp -d "$runtime_root/java.XXXXXX")"
  tar -xzf "$java_archive" -C "$staging"
  java_home="$(find "$staging" -type d -path '*/Contents/Home' -print -quit)"
  if [ -z "$java_home" ] || [ ! -x "$java_home/bin/java" ]; then echo "Java archive has an unexpected layout"; exit 1; fi
  printf '%s\n' "$java_home" > "$runtime_root/java-home.txt"
fi
export JAVA_HOME="$java_home"
export PATH="$JAVA_HOME/bin:$PATH"
"$JAVA_HOME/bin/java" -version
printf 'Python: %s\nGhidra: %s\n' "$python_bin" "$ghidra_home"
# Versioned environment: no changes to a user's system Python packages.
venv="$runtime_root/python-ghidra-12.2"
if [ ! -x "$venv/bin/python3" ]; then "$python_bin" -m venv "$venv"; fi
"$venv/bin/python3" -m pip install --no-index --find-links "$ghidra_home/Ghidra/Features/PyGhidra/pypkg/dist" 'pyghidra==3.2.0' 'JPype1==1.5.2'
(
  cd "$ghidra_home/support/gradle"
  ./gradlew buildNatives
)
config_tmp="$runtime_root/runtime.json.tmp"
"$venv/bin/python3" - "$venv/bin/python3" "$ghidra_home" "$java_home" "$config_tmp" <<'PY'
import json,os,sys
with open(sys.argv[4],'w') as f:
    json.dump(dict(python=sys.argv[1],ghidra=sys.argv[2],javaHome=sys.argv[3]),f,indent=2)
    f.flush();os.fsync(f.fileno())
PY
mv "$config_tmp" "$runtime_root/runtime.json"
echo "Setup complete. In Dissect, open Engine Settings → Reload Configuration → Check Engine."
echo "Log: $log"
