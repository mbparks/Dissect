// Compile with Models.swift and EngineClient.swift. Put Engine/ beside the executable.
import Foundation

@main struct EngineSmoke {
    @MainActor static func main() async throws {
        let environment=ProcessInfo.processInfo.environment
        let config=RuntimeConfig(python: environment["DISSECT_PYTHON"]!, ghidra: environment["GHIDRA_INSTALL_DIR"]!, javaHome: environment["JAVA_HOME"]!)
        let client=EngineClient()
        try client.start(config)
        defer { client.stop() }
        let doctor: DoctorResult=try await client.call("doctor")
        precondition(doctor.ghidra == "12.2")
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let sample=URL(fileURLWithPath: environment["DISSECT_SAMPLE"]!)
        let info: WorkspaceInfo=try await client.call("create", ["source":.string(sample.path),"workspace":.string(temp.appendingPathComponent("test.dissect").path)])
        precondition(info.opened && info.analysis == "complete")
        let page: IndexPage=try await client.call("index", ["kind":.string("functions"),"query":.string("alarm_for_temperature")])
        precondition(!page.items.isEmpty)
        let address=page.items[0].address
        let detail: FunctionDetail=try await client.call("function", ["address":.string(address)])
        precondition(detail.code.contains("alarm_for_temperature"))
        let _: WorkspaceInfo=try await client.call("edit", ["address":.string(address),"operation":.string("note"),"value":.string("Swift → Python → Ghidra 🛠")])
        let note: FunctionDetail=try await client.call("function", ["address":.string(address)])
        precondition(note.note == "Swift → Python → Ghidra 🛠")
        do {
            let _: WorkspaceInfo=try await client.call("edit", ["address":.string(address),"operation":.string("rename"),"value":.string("bad name")])
            fatalError("Invalid rename was accepted")
        } catch { precondition(error.localizedDescription.contains("letters")) }
        let closed: WorkspaceInfo=try await client.call("close")
        precondition(!closed.opened)
        print("Swift IPC smoke passed: startup, typed import, pagination, decompilation, Unicode edits, error delivery, close.")
    }
}
