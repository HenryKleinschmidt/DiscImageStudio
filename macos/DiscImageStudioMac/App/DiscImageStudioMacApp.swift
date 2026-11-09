import DiscImageStudioKit
import SwiftUI

@main
struct DiscImageStudioMacApp: App {
    @StateObject private var model: WorkspaceViewModel

    init() {
        DebugSupport.runPreflightIfRequested()
        _model = StateObject(wrappedValue: WorkspaceViewModel())
    }

    var body: some Scene {
        Window("Disc Image Studio", id: "main") {
            RootView(model: model)
                .frame(minWidth: 1080, minHeight: 700)
                .preferredColorScheme(nil)
        }
        .defaultSize(width: 1360, height: 880)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            AppCommands(model: model)
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 660, height: 560)
        }
    }
}

struct AppCommands: Commands {
    @ObservedObject var model: WorkspaceViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…") { model.presentNewProject() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Open Project…") { model.presentOpenProjectPanel() }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { _ = model.saveProject() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.hasProject)
            Button("Save As…") { model.presentSaveAsPanel() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!model.hasProject)
        }

        CommandMenu("Disc") {
            Button("Import Images…") { model.chooseImages() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!model.hasProject)
            Divider()
            ForEach(Workspace.allCases) { workspace in
                Button(workspace.title) { model.workspace = workspace }
                    .keyboardShortcut(KeyEquivalent(Character(String(Workspace.allCases.firstIndex(of: workspace)! + 1))), modifiers: .command)
                    .disabled(!model.hasProject)
            }
            Divider()
            Button("Generate Image") { model.generateImage() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!model.hasProject || model.isExporting)
            Button("Project Settings…") { model.isProjectSettingsPresented = true }
                .keyboardShortcut(",", modifiers: [.command, .shift])
                .disabled(!model.hasProject)
            Divider()
            Button("Close Project") { model.closeProject() }
                .disabled(!model.hasProject)
        }

        CommandGroup(replacing: .appInfo) {
            Button("About Disc Image Studio") { model.presentAbout() }
        }
    }
}
