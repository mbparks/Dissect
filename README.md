# Dissect

A native Apple Silicon front end for Ghidra: import a binary, explore functions
and strings, read decompiled code, follow references, and keep notes in one
quiet workspace. Independent software by Green Shoe Garage.

## Download and run

The **Dissect-v0.1.1-Apple-Silicon.zip** build artifact contains a compiled
`Dissect.app` with Ghidra, its ARM64 native decompiler, Java and Python included.
Unzip, drag to Applications and open. Requires macOS 14+ and Apple Silicon.
No developer tools or additional downloads are needed to analyze files.

This is an ad-hoc signed preview, not Developer ID signed or notarized.
If macOS blocks this copy, use its per-app **Privacy & Security → Open Anyway**
control. See [START-HERE.txt](START-HERE.txt) for first use and recovery.

## Features

- Local binary import with an untouched original saved in each workspace.
- Search functions and defined strings; decompiled C, assembly and bytes.
- Follow caller/string references and navigate to addresses.
- Raw firmware language, compiler and load-address selection.
- Define a function at a known entry point.
- Rename, annotate, edit C function signatures, and undo/redo annotation edits.
- Save/reopen `.dissect` workspaces; export decompiled code.
- System, light, dark and high-contrast appearance.

This preview does not replace the full Ghidra UI. Complex memory maps,
processor-context controls, debugger integrations and graph views remain
future work. Binaries are analyzed locally, not executed by Dissect.

## Build

Open `Dissect.xcodeproj` with Xcode 15 or later, or run
`bash Build-Dissect.command` for an app using an externally configured engine.
The GitHub Actions workflow builds the self-contained app on a native Apple
Silicon Mac, downloads pinned dependencies, builds Ghidra's native components,
signs nested code, then tests the actual packaged application.

To reproduce the bundled build locally, follow `.github/workflows/macos.yml`.
The runner executes Swift tests, Python storage tests, real Ghidra workflows,
and an opt-in `--smoke-test <report.json>` that launches the native window,
imports an ARM64 fixture, decompiles it and verifies saved annotations.
Build logs, signature verification and launch evidence are separate artifacts.

Source architecture and workspace format are documented under `docs/`.
See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for bundled dependency notices.
