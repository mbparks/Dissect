import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: WorkspaceModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.busy {
            let alert=NSAlert(); alert.messageText="An operation is still running"
            alert.informativeText="Cancel the operation or let it finish before quitting. Completed edits are already saved."
            alert.addButton(withTitle: "Keep Working"); alert.addButton(withTitle: "Cancel Operation")
            if alert.runModal() == .alertSecondButtonReturn { model.engine.cancel() }
            return .terminateCancel
        }
        model.shutdown { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
@main @MainActor struct DissectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model=WorkspaceModel()
    @AppStorage("appearance") private var appearance="system"
    var body: some Scene {
        Window("Dissect", id: "main") {
            WorkspaceView().environmentObject(model)
                .preferredColorScheme(appearance == "system" ? nil : (appearance == "light" ? .light : .dark))
                .frame(minWidth: 1040, minHeight: 680)
                .onAppear { delegate.model=model; model.runLaunchCheckIfRequested() }
                .onOpenURL { model.stageImport($0) }
        }
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Binary…", action: model.chooseImport).keyboardShortcut("n").disabled(model.busy)
                Button("Open Workspace…", action: model.chooseWorkspace).keyboardShortcut("o").disabled(model.busy)
            }
            CommandGroup(after: .saveItem) {
                Button("Export Decompiled Code…", action: model.exportCode).keyboardShortcut("e", modifiers: [.command, .shift]).disabled(model.function == nil || model.busy)
                Button("Reveal Workspace", action: model.revealWorkspace).disabled(!model.isOpen)
            }
            CommandMenu("Analysis") {
                Button("Run Analysis", action: model.analyze).disabled(!model.isOpen || model.busy)
                Button("Cancel Operation") { model.engine.cancel() }.keyboardShortcut(".").disabled(!model.busy)
                Divider()
                Button("Undo Last Analysis Edit") { model.undoRedo("undo") }.disabled(model.workspace?.canUndo != true || model.busy)
                Button("Redo Analysis Edit") { model.undoRedo("redo") }.disabled(model.workspace?.canRedo != true || model.busy)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Engine Settings…") { model.settingsPresented=true }.keyboardShortcut(",")
            }
        }
    }
}
