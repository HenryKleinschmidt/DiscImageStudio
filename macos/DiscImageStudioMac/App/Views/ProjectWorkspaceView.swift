import DiscImageStudioKit
import SwiftUI

struct ProjectWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel

    // List requires an optional selection; ignore transient deselection so a workspace stays open.
    private var selection: Binding<Workspace?> {
        Binding(get: { model.workspace }, set: { if let value = $0 { model.workspace = value } })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section("Workspace") {
                    ForEach(Workspace.allCases) { workspace in
                        Label(workspace.title, systemImage: workspace.systemImage)
                            .tag(workspace)
                            .help(workspace.subtitle)
                    }
                }
                Section("Project") {
                    LabeledContent("Disc", value: model.family.label)
                    LabeledContent("Layers", value: "\(model.state?.layers.count ?? 0)")
                    LabeledContent("Output", value: model.outputDisplayName)
                        .lineLimit(1)
                        .help(model.state?.outputs.outputPath ?? "")
                }
                .foregroundStyle(.secondary)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.cliDetection.hasPrefix("Not found") ? "Engine not found" : "Engine ready",
                          systemImage: model.cliDetection.hasPrefix("Not found") ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.callout)
                        .help(model.cliDetection)
                    SettingsLink { Label("Settings…", systemImage: "gearshape") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        } detail: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.pageBackground)
                .navigationTitle(model.projectDisplayName)
                .navigationSubtitle("\(model.workspace.title) · \(model.statusBadge)\(model.isDirty ? " · Edited" : "")")
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button { _ = model.saveProject() } label: {
                            Label("Save Project", systemImage: "square.and.arrow.down")
                        }
                        .help("Save project (⌘S)")
                        Button { model.isProjectSettingsPresented = true } label: {
                            Label("Project Settings", systemImage: "slider.horizontal.3")
                        }
                        .help("Project settings (⇧⌘,)")
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        if model.workspace == .design {
                            Button { model.chooseImages() } label: {
                                Label("Import Images…", systemImage: "photo.badge.plus")
                            }
                            .help("Import images (⇧⌘I)")
                        }
                        if model.workspace == .preview {
                            Button { model.renderPreview() } label: {
                                Label("Render Preview", systemImage: "arrow.clockwise")
                            }
                            .disabled((model.state?.layers.isEmpty ?? true) || model.isPreviewing)
                        }
                        Button { model.generateImage() } label: {
                            Label("Generate Image", systemImage: "arrow.down.circle")
                        }
                        .help("Generate disc image (⇧⌘E)")
                        .disabled(!model.canExport || model.isExporting)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if supportsInspector {
                            Button { model.isInspectorPresented.toggle() } label: {
                                Label("Toggle Inspector", systemImage: "sidebar.right")
                            }
                            .help("Show or hide inspector (⌥⌘I)")
                        }
                    }
                }
        }
    }

    private var supportsInspector: Bool {
        [.design, .preview, .calibration].contains(model.workspace)
    }

    @ViewBuilder private var content: some View {
        switch model.workspace {
        case .design: DesignView(model: model)
        case .preview: PreviewView(model: model)
        case .export: ExportView(model: model)
        case .calibration: CalibrationView(model: model)
        case .burn: BurnView(model: model)
        }
    }
}
