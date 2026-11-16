# Roadmap

| Milestone | Outcome | Status |
|---|---|---|
| 0.1.0 source preview | Import/analyze, functions/strings/references, decompilation, raw entry definition, saved edits, cancellation, native app source | Implemented; engine tested on Linux; Mac acceptance pending |
| 0.2 Mac acceptance | Build and launch on Apple Silicon; exercise dialogs, keyboard, file associations, resize, appearances, setup, and recovery; fix observed problems | Next |
| 0.3 firmware workflow | Multi-region memory map, entry points, Thumb/context controls, type browser, structural undo and call graphs | Planned |
| 0.4 comparison and reports | Binary comparison, searchable analysis notes, navigable exports and project handoff | Planned |
| 1.0 distribution | Signed runtimes, supported update policy, reproducible Mac CI, Developer ID signing/notarization, installer UX | Planned; requires distribution credentials/decisions |

Live debugging, patching, arbitrary script execution, and full Ghidra GUI-plugin
compatibility are outside this first release. They require separate design and
acceptance, not just adding buttons to the new interface.
