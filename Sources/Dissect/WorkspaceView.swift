import SwiftUI
import AppKit

@MainActor struct WorkspaceView: View {
    @EnvironmentObject private var model: WorkspaceModel
    @AppStorage("appearance") private var appearance="system"
    @State private var detailTab="code"
    @State private var editOperation: String?
    @State private var editText=""
    @State private var address=""
    private var contrast: Bool { appearance == "contrast" }
    var body: some View {
        VStack(spacing: 0) {
            if model.isOpen { workspace } else { welcome }
            Divider()
            HStack(spacing: 10) {
                if model.busy { ProgressView().controlSize(.small); Button("Cancel") { model.engine.cancel() } }
                else { Image(systemName: "internaldrive").foregroundStyle(.secondary) }
                Text(model.status).font(.caption).lineLimit(2)
                Spacer()
                Text("LOCAL ANALYSIS").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.vertical, 9)
        }
        .background(contrast ? Color.black : Color(nsColor: .windowBackgroundColor))
        .foregroundColor(contrast ? .white : .primary)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: model.chooseImport) { Label("Import", systemImage: "square.and.arrow.down") }.help("Import a binary into a new workspace").disabled(model.busy)
                Button(action: model.chooseWorkspace) { Label("Open", systemImage: "folder") }.help("Open saved workspace").disabled(model.busy)
            }
            ToolbarItemGroup {
                if model.isOpen {
                    Button(action: model.goBack) { Label("Back", systemImage: "chevron.left") }.disabled(model.history.isEmpty || model.busy)
                    Button(action: model.analyze) { Label("Analyze", systemImage: "waveform.path.ecg") }.disabled(model.busy)
                    Button { model.undoRedo("undo") } label: { Label("Undo Edit", systemImage: "arrow.uturn.backward") }.disabled(model.workspace?.canUndo != true || model.busy)
                    Button(action: model.exportCode) { Label("Export Code", systemImage: "square.and.arrow.up") }.disabled(model.function == nil || model.busy)
                }
                Button { model.settingsPresented=true } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
        .sheet(isPresented: $model.settingsPresented) { EngineSettingsView().environmentObject(model) }
        .sheet(isPresented: $model.importPresented) { ImportView().environmentObject(model) }
        .sheet(isPresented: Binding(get: { editOperation != nil }, set: { if !$0 { editOperation=nil } })) { editSheet }
        .alert("Dissect", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage=nil } })) {
            Button("OK", role: .cancel) { model.errorMessage=nil }
            Button("Engine Settings") { model.errorMessage=nil; model.settingsPresented=true }
        } message: { Text(model.errorMessage ?? "") }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url=urls.first, !model.busy else { return false }
            model.stageImport(url); return true
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "viewfinder").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(contrast ? Color.white : Color.accentColor)
            VStack(alignment: .leading, spacing: 10) {
                Text("See what’s inside.").font(.system(size: 38, weight: .semibold, design: .rounded))
                Text("A quieter workspace for binary and firmware analysis.")
                    .font(.title3).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Import Binary…", action: model.chooseImport).buttonStyle(.borderedProminent).controlSize(.large)
                Button("Open Workspace…", action: model.chooseWorkspace).controlSize(.large)
            }.disabled(model.busy)
            Text("Or drop a binary or .dissect workspace here.").font(.callout).foregroundStyle(.secondary)
            Divider().frame(width: 520)
            HStack(alignment: .top, spacing: 24) {
                welcomeStep("1", "Import", "Keep an untouched copy of your file.")
                welcomeStep("2", "Explore", "Follow functions, strings, and callers.")
                welcomeStep("3", "Understand", "Rename, annotate, and save your work.")
            }
            Button("Included engine & appearance settings") { model.settingsPresented=true }.buttonStyle(.link)
            Text("Imported binaries are analyzed locally and never executed by Dissect.").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(36)
    }
    private func welcomeStep(_ number: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(number).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(width: 158, alignment: .leading)
    }
    private var workspace: some View {
        HSplitView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.workspace?.name ?? "Binary").font(.headline).lineLimit(1).help(model.workspace?.name ?? "")
                    Text(model.workspace?.language ?? "").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Picker("Browse", selection: $model.kind) { Text("Functions").tag("functions"); Text("Strings").tag("strings") }.pickerStyle(.segmented)
                    .onChange(of: model.kind) { _ in if model.isOpen && !model.busy { model.refresh() } }
                HStack {
                    TextField("Search name, text, or address", text: $model.query).textFieldStyle(.roundedBorder).onSubmit { model.refresh() }
                    Button(action: model.refresh) { Image(systemName: "magnifyingglass") }.help("Search all results")
                }
                List(selection: $model.selection) {
                    ForEach(model.rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name).font(.system(.body, design: .monospaced)).lineLimit(2)
                            Text(row.address).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                        }.padding(.vertical, 3).tag(row.id)
                    }
                }.listStyle(.sidebar).onChange(of: model.selection) { value in model.select(value) }
                HStack {
                    Button { model.page(-1) } label: { Image(systemName: "chevron.left") }.disabled(model.offset == 0).help("Previous page")
                    Spacer()
                    Text("\(model.total == 0 ? 0 : model.offset + 1)–\(model.offset + model.rows.count) of \(model.total)").font(.caption)
                    Spacer()
                    Button { model.page(1) } label: { Image(systemName: "chevron.right") }.disabled(!model.hasMore).help("Next page")
                }
            }.padding(14).frame(minWidth: 240, idealWidth: 280, maxWidth: 380).disabled(model.busy)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.function?.name ?? (model.kind == "strings" ? "String references" : "Select a function")).font(.title3).textSelection(.enabled)
                        Text(model.function?.signature ?? model.selectedRow?.name ?? "").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                    }
                    Spacer()
                    if let f=model.function {
                        Menu {
                            Button("Rename Function…") { beginEdit("rename", f.name) }
                            Button("Edit Function Signature…") { beginEdit("signature", f.signature) }
                            Button("Edit Note…") { beginEdit("note", f.note) }
                        } label: { Label("Edit", systemImage: "pencil") }.disabled(model.busy)
                    }
                }.padding(16)
                Picker("Detail", selection: $detailTab) {
                    Text("Decompiled Code").tag("code"); Text("Assembly").tag("assembly"); Text("Bytes").tag("bytes")
                }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 12)
                if let warning=model.function?.warning, !warning.isEmpty {
                    Label(warning, systemImage: "exclamationmark.triangle").font(.caption).padding(12).foregroundStyle(Color.orange)
                }
                Divider()
                CodeView(text: detailText, syntax: detailTab == "code" && model.function != nil, highContrast: contrast)
            }.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            inspector.frame(minWidth: 240, idealWidth: 270, maxWidth: 360)
        }
    }
    private var detailText: String {
        if detailTab == "bytes" { return model.bytes }
        guard let f=model.function else { return model.kind == "strings" ? "Select a reference on the right to inspect the function using this string." : "Select a function to see its reconstructed code.\n\nNo functions found? For raw firmware, verify its processor and image base when importing." }
        if detailTab == "assembly" { return f.assembly }
        return f.code.isEmpty ? "No decompiled output is available. Check the warning above or view Assembly." : f.code
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("REFERENCES").font(.system(.caption, design: .monospaced)).fontWeight(.semibold); Spacer(); Text("\(model.references.count)").foregroundStyle(.secondary) }
            Text("Addresses that point here. Select one to follow its containing function.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if model.references.isEmpty { Text("No references found.").font(.callout).foregroundStyle(.secondary).padding(.vertical) }
                    ForEach(Array(model.references.enumerated()), id: \.offset) { _, row in
                        Button { model.navigate(row.address) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.name).font(.system(.callout, design: .monospaced)).lineLimit(1)
                                Text("\(row.address) · \(row.detail)").font(.caption2).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }.buttonStyle(.plain).background(Color.primary.opacity(0.045)).cornerRadius(6)
                    }
                    if model.referencesTruncated { Text("Showing first 1,000 references.").font(.caption) }
                }
            }.frame(minHeight: 120)
            Divider()
            HStack {
                Text("FUNCTION NOTE").font(.system(.caption, design: .monospaced)).fontWeight(.semibold)
                Spacer()
                if let f=model.function { Button("Edit") { beginEdit("note", f.note) } }
            }
            ScrollView { Text(model.function?.note.isEmpty == false ? model.function!.note : "Add context as you learn what this function does.").font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 120)
            Divider()
            Text("GO TO ADDRESS").font(.system(.caption, design: .monospaced)).fontWeight(.semibold)
            HStack { TextField("Hex address", text: $address).textFieldStyle(.roundedBorder).onSubmit { model.navigate(address) }; Button("Go") { model.navigate(address) }.disabled(address.isEmpty) }
            Button("Define Function at Address") { model.defineFunction(address) }.disabled(address.isEmpty).help("Disassemble and define a function here. Starts a new annotation undo history.")
            Text("Image base: \(model.workspace?.imageBase ?? "—")\nAnalysis: \(model.workspace?.analysis ?? "—")").font(.caption).foregroundStyle(.secondary)
            Button("Reveal saved workspace", action: model.revealWorkspace).buttonStyle(.link).font(.caption)
        }.padding(16).disabled(model.busy)
    }
    private func beginEdit(_ operation: String, _ value: String) { model.errorMessage=nil; editText=value; editOperation=operation }
    private var editSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editOperation == "note" ? "Function note" : editOperation == "rename" ? "Rename function" : "Function signature").font(.title2)
            Text(editOperation == "signature" ? "Enter a C function declaration. Parameter and return types update the analysis." : "Changes are saved in the Ghidra project; the original binary stays untouched.").font(.callout).foregroundStyle(.secondary)
            if editOperation == "note" { TextEditor(text: $editText).font(.body).frame(height: 210).border(Color.secondary.opacity(0.3)) }
            else { TextField("Value", text: $editText).font(.system(.body, design: .monospaced)).textFieldStyle(.roundedBorder) }
            if let error=model.errorMessage { Text(error).font(.callout).foregroundStyle(Color.red) }
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { editOperation=nil }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Button("Save") { if let op=editOperation { model.edit(op, value: editText) { editOperation=nil } } }.keyboardShortcut(.defaultAction).disabled(model.busy)
            }
        }.padding(24).frame(width: 600)
    }
}
