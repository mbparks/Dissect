#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DISSECT_PYTHON:?Set DISSECT_PYTHON to the engine virtualenv Python executable}"
: "${GHIDRA_INSTALL_DIR:?Set GHIDRA_INSTALL_DIR to Ghidra 12.2}"
: "${JAVA_HOME:?Set JAVA_HOME to a JDK 25 home}"
mkdir -p build
run_dir="$(mktemp -d "$PWD/build/bridge.XXXXXX")"
cp -R Resources/Engine "$run_dir/Engine"
swiftc -swift-version 5 -parse-as-library Sources/DissectCore/Models.swift Sources/Dissect/EngineClient.swift tests/EngineSmoke.swift -o "$run_dir/engine-smoke"
cc -O0 -g -fno-inline examples/thermostat.c -o "$run_dir/thermostat"
DISSECT_SAMPLE="$run_dir/thermostat" "$run_dir/engine-smoke"
