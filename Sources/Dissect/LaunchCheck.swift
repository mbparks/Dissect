import Foundation

// Opt-in release check using the actual model, bundled runtime and views.
extension WorkspaceModel {
    func runLaunchCheckIfRequested() {
        let args=CommandLine.arguments
        guard !launchCheckStarted, let i=args.firstIndex(of: "--smoke-test"), i+1 < args.count else { return }
        launchCheckStarted=true; busy=true
        let report=URL(fileURLWithPath: args[i+1])
        Task { @MainActor in
            var checks=[String]()
            let workspaceURL=report.deletingLastPathComponent().appendingPathComponent("launch-test.dissect")
            do {
                guard let config=RuntimeConfig.bundled(),
                      let sample=Bundle.main.resourceURL?.appendingPathComponent("Samples/firmware-arm64-macho.o") else {
                    throw EngineClient.Failure(message: "Bundled runtime or sample is missing")
                }
                try engine.start(config)
                let doctor: DoctorResult=try await engine.call("doctor")
                guard doctor.ghidra == "12.2", doctor.architecture == "aarch64" || doctor.architecture == "arm64" else {
                    throw EngineClient.Failure(message: "Unexpected runtime: \(doctor)")
                }
                checks.append("Native window and bundled ARM64 engine started")
                workspace=try await engine.call("create", ["source": .string(sample.path), "workspace": .string(workspaceURL.path)])
                kind="functions"; query="alarm_for_temperature"
                try await loadPage(selectFirst: true)
                guard let f=function, !f.code.isEmpty, f.warning.isEmpty, !f.assembly.isEmpty else {
                    throw EngineClient.Failure(message: "ARM64 sample did not decompile")
                }
                checks.append("Imported ARM64 Mach-O; populated code, assembly, references and bytes")
                let note="Bundled Apple Silicon app: save/reopen check 🛠"
                workspace=try await engine.call("edit", ["address": .string(f.address), "operation": .string("note"), "value": .string(note)])
                workspace=try await engine.call("close")
                workspace=try await engine.call("open", ["workspace": .string(workspaceURL.path)])
                try await loadPage(selectFirst: true)
                guard function?.note == note else { throw EngineClient.Failure(message: "Saved note did not survive reopening") }
                checks.append("Saved and reopened workspace with Unicode annotation intact")
                engineSummary="Ghidra \(doctor.ghidra) • Java \(doctor.java) • \(doctor.architecture)"
                status="Workspace changes are saved locally."; busy=false
                let data=try JSONSerialization.data(withJSONObject: ["success": true, "checks": checks, "engine": engineSummary, "bundle": Bundle.main.bundleURL.path], options: [.prettyPrinted, .sortedKeys])
                try data.write(to: report, options: .atomic)
            } catch {
                busy=false; status=error.localizedDescription
                let data=try? JSONSerialization.data(withJSONObject: ["success": false, "error": error.localizedDescription, "checks": checks, "log": engine.diagnosticLog], options: [.prettyPrinted, .sortedKeys])
                try? data?.write(to: report, options: .atomic)
            }
        }
    }
}
