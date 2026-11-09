import DiscImageStudioKit
import SwiftUI

struct ProjectWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 205, ideal: Theme.sidebarWidth, max: 280)
        } detail: {
            VStack(spacing: 0) {
                workspaceHeader
                Divider().opacity(0.6)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.pageBackground)
            .navigationTitle(model.projectDisplayName)
            .navigationSubtitle(model.statusBadge)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        _ = model.saveProject()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .help("Save project (⌘S)")
                    .disabled(!model.hasProject)

                    Button {
                        model.isProjectSettingsPresented = true
                    } label: {
                        Label("Project settings", systemImage: "slider.horizontal.3")
                    }
                    .help("Project geometry and preset")

                    Button {
                        model.generateImage()
                    } label: {
                        Label("Generate", systemImage: "arrow.down.circle")
                    }
                    .help("Generate the disc image (⇧⌘E)")
                    .disabled(!model.canExport || model.isExporting)
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Theme.accent, Theme.accentDeep],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: "opticaldiscdrive.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.projectDisplayName)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            FamilyBadge(family: model.family, compact: true)
                            if model.isDirty {
                                Text("Unsaved")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Theme.amber)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            List {
                Section("Workspace") {
                    ForEach(Workspace.allCases) { workspace in
                        Button {
                            model.workspace = workspace
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: workspace.systemImage)
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(width: 18)
                                    .foregroundStyle(model.workspace == workspace ? Theme.accent : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(workspace.title)
                                        .font(.system(size: 12.5, weight: model.workspace == workspace ? .semibold : .regular))
                                    Text(workspace.subtitle)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if model.workspace == workspace {
                                    Circle().fill(Theme.accent).frame(width: 5, height: 5)
                                }
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Project") {
                    sidebarRow("Disc", value: model.family.label, icon: "opticaldisc")
                    sidebarRow("Layers", value: "\(model.state?.layers.count ?? 0)", icon: "square.3.layers.3d")
                    sidebarRow(
                        "Output",
                        value: model.outputDisplayName,
                        icon: "doc"
                    )
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.cliDetection.hasPrefix("Not found") ? Theme.amber : Theme.mint)
                        .frame(width: 6, height: 6)
                    Text(model.cliDetection.hasPrefix("Not found") ? "Engine not found" : "Engine ready")
                        .font(.system(size: 10.5, weight: .semibold))
                    Spacer()
                    SettingsLink {
                        Text("Settings")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Text(model.cliDetection)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 7) {
                    Button {
                        model.closeProject()
                    } label: {
                        Label("Home", systemImage: "house")
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    Button {
                        _ = model.saveProject()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .disabled(!model.hasProject)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.025))
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
    }

    private func sidebarRow(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 1)
    }

    private var workspaceHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: model.workspace.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(model.workspace.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                Text(headerSubtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch model.workspace {
            case .design:
                Button {
                    model.chooseImages()
                } label: {
                    Label("Import images", systemImage: "photo.badge.plus")
                }
                .buttonStyle(PrimaryActionButtonStyle())
            case .preview:
                if model.isPreviewing {
                    ProgressView().controlSize(.small)
                }
                Button {
                    model.renderPreview()
                } label: {
                    Label("Render preview", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!model.hasProject || (model.state?.layers.isEmpty ?? true))
            case .export:
                Button {
                    model.generateImage()
                } label: {
                    Label("Generate image", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!model.canExport || model.isExporting)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
    }

    private var headerSubtitle: String {
        switch model.workspace {
        case .design:
            return "Layers are flattened in millimetres, then handed to the physical disc engine at export."
        case .preview:
            return "Projection follows the current project geometry; measured radii only affect inspection."
        case .export:
            return "The same 8192 px composite used for preview is written into the disc image."
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.workspace {
        case .design:
            DesignView(model: model)
        case .preview:
            PreviewView(model: model)
        case .export:
            ExportView(model: model)
        }
    }
}
