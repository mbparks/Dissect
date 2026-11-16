# Dissect workspace format, schema 1

`.dissect` is a macOS package directory:

| Path | Meaning |
|---|---|
| `workspace.json` | UTF-8 manifest; format `dissect-workspace`, schema `1` |
| `original.bin` | Untouched imported bytes, not marked executable |
| `database/Dissect.gpr` | Standard Ghidra 12.2 project descriptor |
| `database/Dissect.rep/` | Ghidra database; imported program path `/Binary` |
| `.dissect.lock` | Process file-lock target; a stale file alone is harmless |

The manifest includes original name, size, SHA-256, creation timestamp (UTC),
program path `/Binary`, and analysis state (`notStarted`, `running`, `complete`,
`interrupted`). Processor/compiler/memory settings and all function annotations
live in the Ghidra program, not duplicated in the manifest.

Unknown schemas are refused without modification. Opening validates the copied
original hash, the fixed program path, and the absence of symlinks in the package.
Do not manually edit database files. A failed initial import may leave an incomplete
package containing the source and metadata; retain it if needed and import again
under a new workspace name. A cancelled analysis after import can be reopened.

For backup, close the workspace and copy the entire package. Never split the
project descriptor from its `.rep` directory. Original user source paths are not
stored in this manifest; the original base filename is retained.
