import SwiftUI
import AppKit

@MainActor struct EngineSettingsView: View {
    @EnvironmentObject private var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance="system"
    @State private var config=RuntimeConfig.load()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Engine & appearance").font(.title2); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Analysis stays on your Mac. This app includes Ghidra 12.2, Java, and Python for Apple Silicon. No separate setup is needed.").foregroundStyle(.secondary)
            HStack {
                if let bundled = RuntimeConfig.bundled() {
                    Button("Use Included Engine") { config=bundled; model.saveConfig(config) }.buttonStyle(.borderedProminent)
                } else {
                    Button("Set Up External Engine…", action: model.setupEngine).buttonStyle(.borderedProminent)
                }
                Button("Reload Configuration") { config=RuntimeConfig.load(); model.saveConfig(config) }
            }.disabled(model.busy)
            Divider()
            Form {
                pathRow("Python executable", value: $config.python, directory: false)
                pathRow("Ghidra folder", value: $config.ghidra, directory: true)
                pathRow("Java home", value: $config.javaHome, directory: true)
            }.disabled(model.busy)
            HStack {
                Button("Save Paths & Restart Engine") { model.saveConfig(config) }.disabled(model.busy)
                Button("Check Engine", action: model.checkEngine).disabled(model.busy || config != RuntimeConfig.load())
                Spacer()
                Button("Copy Diagnostic Log", action: model.copyDiagnostics)
            }
            if let error=model.errorMessage { Text(error).font(.callout).foregroundStyle(Color.red).textSelection(.enabled) }
            Text(model.engineSummary).font(.callout).textSelection(.enabled)
            Text("Changing engine paths closes the current workspace. Saved edits are preserved.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark"); Text("High contrast").tag("contrast")
            }.pickerStyle(.segmented)
            Text("Dissect 0.1.1 • Native macOS preview • Powered by Ghidra\nIndependent software by Green Shoe Garage; not affiliated with or endorsed by the NSA.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 700)
    }
    private func pathRow(_ title: String, value: Binding<String>, directory: Bool) -> some View {
        HStack {
            TextField(title, text: value).textFieldStyle(.roundedBorder)
            Button("Choose…") {
                let panel=NSOpenPanel(); panel.title=title; panel.canChooseDirectories=directory; panel.canChooseFiles = !directory
                panel.treatsFilePackagesAsDirectories=true
                if panel.runModal() == .OK, let url=panel.url { value.wrappedValue=url.path }
            }
        }
    }
}

@MainActor struct ImportView: View {
    @EnvironmentObject private var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var raw=false
    @State private var language=""
    @State private var compiler=""
    @State private var base=""
    @State private var filter=""
    private var filtered: [Language] { model.languages.filter { filter.isEmpty || ($0.id + " " + $0.name).localizedCaseInsensitiveContains(filter) } }
    private var compilers: [String] { model.languages.first(where: { $0.id == language })?.compilers ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Import a binary").font(.title2)
            Text(model.sourceURL?.lastPathComponent ?? "No file selected").font(.headline).textSelection(.enabled)
            Text("Dissect copies the original into a new workspace, detects its format, and runs Ghidra analysis. Existing files are not overwritten.").foregroundStyle(.secondary)
            Toggle("This is raw firmware — choose its processor", isOn: $raw)
            if raw {
                HStack {
                    TextField("Filter processors (ARM, AVR, Xtensa…)", text: $filter).textFieldStyle(.roundedBorder)
                    Button("Load Processors", action: model.loadLanguages).disabled(model.busy)
                }
                Picker("Processor / language", selection: $language) {
                    Text("Choose a processor").tag("")
                    ForEach(filtered) { entry in Text(entry.id + " — " + entry.name).tag(entry.id) }
                }.onChange(of: language) { _ in compiler=compilers.first ?? "" }
                Picker("Compiler convention", selection: $compiler) {
                    Text("Default").tag("")
                    ForEach(compilers, id: \.self) { Text($0).tag($0) }
                }
                TextField("Image base (hex, optional; e.g. 08000000)", text: $base).textFieldStyle(.roundedBorder)
                Text("Raw images do not describe their CPU or memory layout. Use the chip’s architecture, endianness, and load address. This preview supports one contiguous image.").font(.caption).foregroundStyle(.secondary)
            }
            if let error=model.errorMessage { Text(error).font(.callout).foregroundStyle(Color.red) }
            HStack {
                if model.busy { ProgressView().controlSize(.small); Text(model.status).font(.caption) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Button("Choose Workspace & Analyze…") { model.importBinary(language: raw ? language : "", compiler: raw ? compiler : "", imageBase: raw ? base : "") }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.busy || (raw && language.isEmpty))
            }
        }.padding(24).frame(width: 680)
    }
}
