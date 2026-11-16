#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p examples/built
cc -O0 -g -fno-inline examples/thermostat.c -o examples/built/thermostat
echo "Import examples/built/thermostat into Dissect. It is a harmless compiled sample; do not need to run it."
