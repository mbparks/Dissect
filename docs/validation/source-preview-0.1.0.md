# Validation record — 0.1.0 source preview

Recorded 2026-11-16. **Source/engine validation, not Mac application acceptance.**

## Environment

- Authoring/test host: Linux x86_64. No macOS host, Xcode, Apple SDK, Apple codesign,
  or authorized project-specific Mac CI runner was available.
- Swift 6.4.2 official Debian toolchain, language mode 5 for the app-client checks.
- Python 3.12, PyGhidra 3.2.0, JPype1 1.5.2.
- Ghidra 12.2 official multi-platform release, SHA-256:
  `2c2cd776db3c1f6a097ba418922378ac3649cadd5e844a6f5f088ae628a7be67`.
- Amazon Corretto JDK 25.0.5; Linux native decompiler from the Ghidra distribution.
- Supplied app targets macOS 14+ / ARM64. No Dissect Mach-O executable was produced.
  The included ARM64 `.o` is an analysis fixture, not an application.

## Commands and results

| Check | Result |
|---|---|
| `swift test` | 5 XCTest cases passed: fragmented/Unicode protocol, malformed frames, frame bound, request escaping, typed workspace decoding |
| `python3 -m unittest discover -s tests -p 'test_*.py' -v` | 9 tests passed: atomic metadata round-trip, schema rejection, input bounds, tamper detection, symlinks, path invariants, write-lock contention |
| `python tests/integration.py` with real Ghidra/JDK environment | 19 workflow assertions passed; see retained `validation/engine-integration.json` |
| `swiftc -swift-version 5 -typecheck Models.swift EngineClient.swift` | Passed against Linux Foundation; not SwiftUI/AppKit typechecking |
| `swiftc -frontend -parse` across all 7 production Swift sources | Passed syntax parsing only |
| Compiled/ran `tests/EngineSmoke.swift` with production EngineClient/Core | Passed real Swift → Python → Ghidra startup, typed import, decompilation, Unicode note editing, error delivery, and close |
| `python3 scripts/check-project.py` | Passed source/resource paths and membership, scheme XML, plist, asset references, target setting checks and command permissions |
| OpenStep parser on `project.pbxproj` | Parsed all 36 project objects |
| `bash -n` on all supplied shell/command scripts | Passed shell syntax checks |
| Final ZIP extraction/checks | Checked for safe paths, expected contents, executable command bits, and exclusion of toolchains/build caches |

Test logs are retained in `docs/validation/`. The Swift Testing framework also prints
“0 tests” after XCTest completes; the 5 tests here are XCTest cases and their complete
passed result appears immediately before that separate empty-framework summary.

## Feature and evidence matrix

| Feature | Implementation | Evidence | Remaining limit |
|---|---|---|---|
| Native Mac window, file panels, drag/drop, themes | Implemented | Source syntax and project consistency | Not compiled or launched on macOS |
| Engine setup/download/build commands | Implemented | Shell syntax; upstream paths/checksum verified; dependency versions exercised on Linux | Mac setup script not run |
| Swift IPC client | Implemented | Compiled and exercised with actual Ghidra worker | Linux Foundation execution, not Mac app execution |
| Executable import and analysis | Implemented | Real Linux ELF and ARM64 Mach-O object fixtures | Large/obfuscated real-world firmware not assessed |
| Raw firmware import and entry definition | Implemented | Explicit x86-64 language/compiler/base, function creation and decompilation | No multi-region or processor context editor |
| Functions, strings, caller references, bytes | Implemented | Real fixture searches, pagination and cross references | UI scrolling/performance untested on Mac |
| Decompiler and assembly | Implemented | Real Ghidra decompilation, including ARM64 code | Native Mac helper execution not tested |
| Rename, C signature, notes | Implemented | Edit, invalid-signature rollback, reload and Unicode checks | Parameter/local-variable editing only via signature; no full type browser |
| Undo/redo | Implemented for annotations | Real rename undo/redo | Session only; function definition is not undoable |
| Save and reopen | Implemented | Real workspace close/reopen and workspace switching | Backup copying while open unsupported |
| Cancellation and recovery | Implemented | Real analysis cancellation, checkpoint, reanalysis | Native app cancel control not clicked on a Mac |
| Original integrity / one writer | Implemented | Hash, schema, symlink and lock tests | Not a security audit or parser sandbox |
| Export reconstructed C | Implemented | Source inspection of native save flow | Mac file dialog/export not exercised |
| ARM64 app build / app signing / launch | Pending | No Mac build environment | Source preview only; no compiled app, notarization, or release claim |
| GitHub Actions | Workflow supplied | YAML/source review | Not run; no repository or release published |

## Required Mac acceptance before a binary release

1. On Apple Silicon/macOS 14+, run setup and the Xcode build. Retain both logs.
2. Launch `dist/Dissect.app`, check engine, and import each bundled fixture.
3. Resize the window, navigate all panes with keyboard/mouse, use text selection
   and find, and inspect system/light/dark/high-contrast appearances.
4. Rename and annotate a function, edit its signature, undo/redo, export C, quit,
   and reopen the workspace from Finder. Verify the notes and types persisted.
5. Try a raw image with a known language and base; define its entry function.
6. Cancel analysis, re-open/reanalyze, and verify previous edits are intact.
7. Check invalid processor/address/signature, inaccessible paths, a second writer,
   and failed/missing dependency recovery. Confirm diagnostics remain useful.
8. Only after those workflows pass, prepare any signed/notarized distribution.
