# Architecture

The SwiftUI/AppKit application owns presentation; one persistent Python worker
owns the open Ghidra project and all mutations. The process boundary lets JVM
startup, imports, analysis, and decompilation run away from the UI thread.

| Component | Responsibility |
|---|---|
| DissectApp / WorkspaceView / SetupViews | Single-window shell, menus, import workflow, views and dialogs |
| CodeView | Native selectable/searchable text, conservative syntax highlighting |
| WorkspaceModel | Main-actor UI state and serial operation orchestration |
| EngineClient | Launch helper without a shell, JSONL request/reply, progress, cancellation, errors |
| DissectCore | Codable contracts, framing, runtime configuration; independently tested Swift package |
| engine.py | Ghidra lifecycle, import/load/analyze/decompile, edits, annotation history |
| storage.py | Schema, original hash, file bounds, symlink rejection, atomic metadata writes |

The main app target compiles the core files directly. The Swift package compiles
those same core files for tests; it is not a second persistence system.

Requests contain a unique ID, allowed method name, and typed parameters. Responses
have the same ID and a result or error. Progress events are separate. Protocol
output has an `@DISSECT@` prefix; Java/Python/native diagnostic stdout is redirected
to stderr at worker startup, keeping logs out of structured replies. Swift bounds
an incomplete frame to 8 MiB. Backend requests are limited to 64 KiB and serialized
through a bounded queue. A reader thread handles cancellation while Java works.

Ghidra 12.2 / PyGhidra 3.2.0 are pinned. PyGhidra cancels its supplied analysis
monitor even on normal completion, so the engine renews that monitor and checks
its own request cancellation flag. Partial analysis is checkpointed on interruption.
Decompilation has a 45-second timeout. Inspection lists are paginated; reference
results cap at 1,000, assembly at 5,000 instructions, code at 2 million characters,
and byte inspection at 256 bytes. Limits are disclosed in views where relevant.
Input binaries are limited to 512 MiB. UI errors preserve existing saved work.

Workspace protection uses both an exclusive OS file lock and Ghidra's project
locking. Rename, signature, and note edits use Ghidra transactions with immediate
save; their previous/new values support a bounded session undo/redo stack. Function
definition is a structural edit and starts a new annotation history. It cannot
be undone through this preview. The copied binary is never modified. Metadata
replacement uses flush/fsync plus rename. Supported schema checks and original
hash verification happen before opening a saved database.

Distribution target is a locally built, unsandboxed Mac application with hardened
runtime. The native app launches user-local Python/Java processes; it does not
embed a JVM in its own process. No broad signing exception entitlements are added.
The supplied script ad-hoc signs the app only; it is not a Developer ID release.
Bundling signed runtimes and notarizing the final product remains future work.
