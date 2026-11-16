import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension UTType { static let dissectWorkspace = UTType(exportedAs: "com.greenshoegarage.dissect.workspace", conformingTo: .package) }

@MainActor final class WorkspaceModel: ObservableObject {
    @Published var workspace: WorkspaceInfo?
    @Published var rows: [AnalysisRow] = []
    @Published var references: [AnalysisRow] = []
    @Published var function: FunctionDetail?
    @Published var selection: String?
    @Published var kind="functions"
    @Published var query=""
    @Published var total=0
    @Published var offset=0
    @Published var hasMore=false
    @Published var bytes=""
    @Published var status="Ready to inspect a binary."
    @Published var busy=false
    @Published var errorMessage: String?
    @Published var settingsPresented=false
    @Published var importPresented=false
    @Published var sourceURL: URL?
    @Published var languages: [Language] = []
    @Published var engineSummary="Engine has not been checked."
    @Published var referencesTruncated=false
    @Published var history: [String] = []
    let engine=EngineClient()
    var launchCheckStarted=false
    var isOpen: Bool { workspace?.opened == true }
    var selectedRow: AnalysisRow? { rows.first { $0.id == selection } }
    init() { engine.onProgress = { [weak self] text in self?.status=text } }

    func run(_ task: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy=true; errorMessage=nil
        Task {
            defer { busy=false }
            do { try engine.start(RuntimeConfig.load()); try await task(); status=isOpen ? "Workspace changes are saved locally." : "Ready." }
            catch {
                errorMessage=error.localizedDescription
                status="Operation stopped. See the message for recovery steps."
                if engine.isRunning, let recovered: WorkspaceInfo = try? await engine.call("status") {
                    let changed = recovered.path != workspace?.path
                    workspace = recovered.opened ? recovered : nil
                    if changed {
                        rows=[]; function=nil; references=[]; bytes=""; selection=nil; total=0; offset=0
                        if recovered.opened, let page: IndexPage = try? await engine.call("index", ["kind": .string(kind), "limit": .number(200)]) {
                            rows=page.items; total=page.total; hasMore=page.hasMore
                        }
                    }
                }
            }
        }
    }
    func chooseImport() {
        guard !busy else { return }
        let panel=NSOpenPanel(); panel.title="Choose a binary or firmware image"; panel.canChooseDirectories=false; panel.allowsMultipleSelection=false
        if panel.runModal() == .OK, let url=panel.url { stageImport(url) }
    }
    func stageImport(_ url: URL) {
        guard !busy else { return }
        if url.pathExtension == "dissect" { openWorkspace(url); return }
        sourceURL=url; importPresented=true
    }
    func importBinary(language: String, compiler: String, imageBase: String) {
        guard let source=sourceURL else { return }
        let panel=NSSavePanel(); panel.title="Save analysis workspace"; panel.nameFieldStringValue=source.deletingPathExtension().lastPathComponent + ".dissect"
        panel.allowedContentTypes=[.dissectWorkspace]; panel.canCreateDirectories=true
        guard panel.runModal() == .OK, let destination=panel.url else { return }
        importPresented=false
        run { [self] in
            workspace=try await engine.call("create", ["source": .string(source.path), "workspace": .string(destination.path), "language": .string(language), "compiler": .string(compiler), "imageBase": .string(imageBase)])
            history=[]; kind="functions"; query=""; offset=0
            try await loadPage(selectFirst: true)
        }
    }
    func chooseWorkspace() {
        let panel=NSOpenPanel(); panel.title="Open Dissect workspace"; panel.allowedContentTypes=[.dissectWorkspace]; panel.treatsFilePackagesAsDirectories=false
        if panel.runModal() == .OK, let url=panel.url { openWorkspace(url) }
    }
    func openWorkspace(_ url: URL) {
        run { [self] in
            workspace=try await engine.call("open", ["workspace": .string(url.path)])
            history=[]; kind="functions"; query=""; offset=0
            try await loadPage(selectFirst: true)
        }
    }
    func loadPage(selectFirst: Bool = false) async throws {
        let page: IndexPage = try await engine.call("index", ["kind": .string(kind), "query": .string(query), "offset": .number(offset), "limit": .number(200)])
        rows=page.items; total=page.total; hasMore=page.hasMore
        if selectFirst || !rows.contains(where: { $0.address == selection }) {
            selection=rows.first?.address
        }
        if let selection { try await loadSelection(selection, isFunction: kind == "functions") }
        else { function=nil; references=[]; bytes="" }
    }
    func refresh() { run { [self] in offset=0; try await loadPage(selectFirst: true) } }
    func page(_ delta: Int) { run { [self] in offset=max(0,offset+delta*200); try await loadPage(selectFirst: true) } }
    func select(_ address: String?) {
        guard let address, !busy else { return }
        run { [self] in try await loadSelection(address, isFunction: kind == "functions") }
    }
    private func loadSelection(_ address: String, isFunction: Bool) async throws {
        let nextFunction: FunctionDetail? = isFunction ? try await engine.call("function", ["address": .string(address)]) : nil
        let refs: ReferencePage = try await engine.call("references", ["address": .string(address)])
        let result: ByteResult = try await engine.call("bytes", ["address": .string(address)])
        function=nextFunction; references=refs.items; referencesTruncated=refs.truncated; bytes=result.text
        if kind == "functions", let nextFunction { selection=rows.first(where: { $0.address == nextFunction.address })?.id }
    }
    func navigate(_ address: String) {
        run { [self] in
            let previous=function?.address
            try await loadSelection(address, isFunction: true)
            if let previous, previous != function?.address { history.append(previous) }
        }
    }
    func defineFunction(_ address: String) {
        run { [self] in
            workspace=try await engine.call("define", ["address": .string(address)])
            kind="functions"; query=""; offset=0
            try await loadPage()
            try await loadSelection(address, isFunction: true)
        }
    }
    func goBack() {
        guard let last=history.last else { return }
        run { [self] in history.removeLast(); try await loadSelection(last, isFunction: true) }
    }
    func edit(_ operation: String, value: String, onSaved: (() -> Void)? = nil) {
        guard let address=function?.address else { return }
        run { [self] in
            workspace=try await engine.call("edit", ["address": .string(address), "operation": .string(operation), "value": .string(value)])
            // Refresh the list and the actual navigated function, even if filtered out of that list.
            let page: IndexPage = try await engine.call("index", ["kind": .string(kind), "query": .string(query), "offset": .number(offset), "limit": .number(200)])
            rows=page.items; total=page.total; hasMore=page.hasMore
            try await loadSelection(address, isFunction: true)
            onSaved?()
        }
    }
    func undoRedo(_ method: String) {
        let address=function?.address
        run { [self] in
            workspace=try await engine.call(method)
            try await loadPage()
            if let address { try await loadSelection(address, isFunction: true) }
        }
    }
    func analyze() {
        run { [self] in workspace=try await engine.call("analyze"); try await loadPage(selectFirst: true) }
    }
    func checkEngine() {
        run { [self] in
            let info: DoctorResult = try await engine.call("doctor")
            engineSummary="Ghidra \(info.ghidra) • Java \(info.java) • \(info.architecture)"
        }
    }
    func loadLanguages() {
        run { [self] in let result: LanguageResult=try await engine.call("languages"); languages=result.languages }
    }
    func saveConfig(_ config: RuntimeConfig) {
        guard !busy else { return }
        Task {
            busy=true
            defer { busy=false }
            do {
                if engine.isRunning { let _: WorkspaceInfo = try await engine.call("close") }
                engine.stop(); workspace=nil; rows=[]; function=nil; references=[]; bytes=""; selection=nil
                try config.save(); engineSummary="Settings saved. Check engine to verify."; status="Engine settings saved."
            } catch { errorMessage=error.localizedDescription }
        }
    }
    func setupEngine() {
        guard !busy else { return }
        guard let url=Bundle.main.url(forResource: "EngineSetup", withExtension: "command") else { errorMessage="Setup script is missing from the application."; return }
        NSWorkspace.shared.open(url)
        engineSummary="Setup opened in Terminal. When it finishes, choose Reload Configuration."
    }
    func revealWorkspace() {
        if let path=workspace?.path { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    }
    func exportCode() {
        guard let function else { return }
        let panel=NSSavePanel(); panel.allowedContentTypes=[.plainText]; panel.nameFieldStringValue=function.name + ".c"
        if panel.runModal() == .OK, let url=panel.url {
            do { try ("/* Decompiled by Ghidra. This is reconstructed code, not original source. */\n"+function.code).write(to: url, atomically: true, encoding: .utf8) }
            catch { errorMessage=error.localizedDescription }
        }
    }
    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(engine.diagnosticLog, forType: .string)
    }
    func shutdown(_ completion: @escaping () -> Void) {
        Task {
            if engine.isRunning && !busy { let _: WorkspaceInfo? = try? await engine.call("close") }
            engine.stop(); completion()
        }
    }
}
