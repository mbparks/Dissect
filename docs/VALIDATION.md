# Validation — compiled Apple Silicon preview

Version 0.1.1 adds a self-contained native macOS build. The GitHub Actions
`Apple Silicon app` workflow runs on an ARM64 macOS 15 host using Xcode.
Only a run that completes all checks produces the app download artifact.

The workflow checks:

- Swift protocol tests and Python workspace-storage tests.
- Release-mode ARM64 application compilation against the macOS SDK.
- SHA256 verification of Ghidra, standalone Python and Java archives.
- Ghidra native compilation on Apple Silicon.
- Inside-out ad-hoc signing and strict bundle signature verification.
- Real Ghidra import, decompilation, references, bytes, editing, undo/redo,
  save/reopen, cancellation recovery, raw firmware and ARM64 Mach-O workflows.
- Launch of the actual signed app from a relocated folder containing spaces.
  Its native window loads an ARM64 sample through the bundled Python/JVM and
  verifies that saved notes survive closing and reopening the workspace.
- Signature verification again after execution, to detect bundle modification.

The separate `macOS-build-evidence` artifact retains the Xcode log, integration
results, actual-app launch report, available window screenshot, signature log,
executable architecture and ZIP checksum. Use the evidence for the same commit
as the app artifact. Failed runs do not represent a finished release.

This is an automated native launch/integration check. It is not a manual test of
every menu, file dialog, drag/drop gesture or accessibility interaction. Large,
obfuscated firmware and complex memory maps have not been qualified. The
preview is not notarized or Developer ID signed and has not had a security audit.

Earlier Linux source-preview validation is retained in
[validation/source-preview-0.1.0.md](validation/source-preview-0.1.0.md).
