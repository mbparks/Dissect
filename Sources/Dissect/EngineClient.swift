import Foundation

@MainActor final class EngineClient {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var errors: Pipe?
    private var frames = FrameDecoder()
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var currentID: String?
    private var generation = UUID()
    var onProgress: ((String) -> Void)?
    var diagnosticLog = ""
    var isRunning: Bool { process?.isRunning == true }

    func start(_ config: RuntimeConfig) throws {
        if isRunning { return }
        guard FileManager.default.isExecutableFile(atPath: config.python), !config.ghidra.isEmpty, !config.javaHome.isEmpty else {
            throw Failure(message: "The analysis runtime could not be found. In Engine Settings choose Use Included Engine, or reinstall the complete Dissect app.")
        }
        guard let script = Bundle.main.resourceURL?.appendingPathComponent("Engine/engine.py"), FileManager.default.fileExists(atPath: script.path) else {
            throw Failure(message: "The engine helper is missing. Reinstall the complete Dissect app.")
        }
        generation = UUID(); let token = generation
        frames = FrameDecoder(); diagnosticLog = ""
        let p = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.executableURL = URL(fileURLWithPath: config.python)
        p.arguments = ["-u", script.path, "--ghidra", config.ghidra]
        var environment = ProcessInfo.processInfo.environment
        environment["JAVA_HOME"] = config.javaHome
        environment["GHIDRA_INSTALL_DIR"] = config.ghidra
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["PYTHONNOUSERSITE"] = "1"
        environment.removeValue(forKey: "PYTHONHOME")
        environment.removeValue(forKey: "PYTHONPATH")
        environment["PATH"] = config.javaHome + "/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        p.environment = environment
        p.standardInput=stdin; p.standardOutput=stdout; p.standardError=stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data=handle.availableData
            if data.isEmpty { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.receive(data)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data=handle.availableData
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.diagnosticLog += String(decoding: data, as: UTF8.self)
                self.diagnosticLog = String(self.diagnosticLog.suffix(32_000))
            }
        }
        p.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.failAll("The analysis engine stopped (status \(status)). Reopen your workspace. Engine Settings contains the diagnostic log.")
            }
        }
        process=p; input=stdin; output=stdout; errors=stderr
        do { try p.run() }
        catch { stop(); throw error }
    }
    func call<T: Decodable>(_ method: String, _ params: [String: JSONValue] = [:], as type: T.Type = T.self) async throws -> T {
        guard isRunning else { throw Failure(message: "The engine is not running. Open Engine Settings to check it.") }
        let id=UUID().uuidString
        let request=EngineRequest(id: id, method: method, params: params)
        var data=try JSONEncoder().encode(request); data.append(10)
        let response: Data = try await withCheckedThrowingContinuation { continuation in
            pending[id]=continuation; currentID=id
            do { try input?.fileHandleForWriting.write(contentsOf: data) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error) }
        }
        return try JSONDecoder().decode(type, from: response)
    }
    func cancel() {
        guard let currentID else { return }
        let request=EngineRequest(id: UUID().uuidString, method: "cancel", params: ["requestID": .string(currentID)])
        if var data=try? JSONEncoder().encode(request) { data.append(10); try? input?.fileHandleForWriting.write(contentsOf: data) }
    }
    private func receive(_ data: Data) {
        do {
            for response in try frames.append(data) {
                if response.event == "progress" { onProgress?(response.message ?? "Working…"); continue }
                guard let id=response.id, let continuation=pending.removeValue(forKey: id) else { continue }
                if currentID == id { currentID=nil }
                if let error=response.error { continuation.resume(throwing: Failure(message: error)) }
                else if let result=response.result {
                    do { continuation.resume(returning: try JSONEncoder().encode(result)) }
                    catch { continuation.resume(throwing: error) }
                } else { continuation.resume(throwing: Failure(message: "The engine returned an empty response.")) }
            }
        } catch { failAll("Could not read the engine response: \(error.localizedDescription)"); stop() }
    }
    private func failAll(_ message: String) {
        let calls=pending; pending.removeAll(); currentID=nil
        for c in calls.values { c.resume(throwing: Failure(message: message)) }
    }
    func stop() {
        generation=UUID()
        output?.fileHandleForReading.readabilityHandler=nil
        errors?.fileHandleForReading.readabilityHandler=nil
        try? input?.fileHandleForWriting.close()
        // Normal callers close the Ghidra project before stopping. This fallback is for a failed engine.
        if process?.isRunning == true { process?.terminate() }
        process=nil; input=nil; output=nil; errors=nil
        failAll("Analysis engine stopped.")
    }
}
