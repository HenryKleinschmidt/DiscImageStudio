import AppKit
import DiscImageStudioKit
import SwiftUI

struct HomeView: View {
    @ObservedObject var model: WorkspaceViewModel
    @ViewState private var selectedRecent: String?
    @ViewState private var searchText = ""

    private var filteredRecents: [RecentProject] {
        model.recentProjects.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.url.path.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedProject: RecentProject? {
        filteredRecents.first { $0.id == selectedRecent }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedRecent) {
                Section("Recent Projects") {
                    ForEach(filteredRecents) { entry in
                        HStack(spacing: 10) {
                            DiscThumbnail(base64: entry.thumbnailPngBase64, size: 32)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name).lineLimit(1)
                                Text(entry.family.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(entry.id)
                        .help(entry.url.path)
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search Recent Projects")
            .contextMenu(forSelectionType: String.self) { ids in
                if let entry = project(for: ids) {
                    Button("Open") { model.openProject(at: entry.url) }
                    Button("Show in Finder") { reveal(entry) }
                    Divider()
                    Button("Remove from Recents", role: .destructive) { remove(entry) }
                }
            } primaryAction: { ids in
                if let entry = project(for: ids) { model.openProject(at: entry.url) }
            }
            .overlay {
                if filteredRecents.isEmpty {
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? "No Recent Projects" : "No Results",
                              systemImage: searchText.isEmpty ? "clock" : "magnifyingglass")
                    } description: {
                        Text(searchText.isEmpty ? "Projects you open appear here." : "Try another name or folder.")
                    } actions: {
                        if !searchText.isEmpty {
                            Button("Clear Search") { searchText = "" }
                        }
                    }
                    .allowsHitTesting(!searchText.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 380)
        } detail: {
            Group {
                if let entry = selectedProject {
                    RecentProjectDetail(entry: entry, open: { model.openProject(at: entry.url) },
                                        reveal: { reveal(entry) }, remove: { remove(entry) })
                        .id(entry.id)
                } else {
                    welcome
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(selectedProject?.name ?? "Disc Image Studio")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    newProjectMenu
                        .help("New project (⌘N); choose a disc medium from the menu")
                    Button { model.presentOpenProjectPanel() } label: {
                        Label("Open Project…", systemImage: "folder")
                    }
                    .help("Open a project (⌘O)")
                }
            }
        }
        .onChange(of: searchText) { _, _ in
            if selectedProject == nil { selectedRecent = nil }
        }
        .onChange(of: model.recentProjects) { _, entries in
            if !entries.contains(where: { $0.id == selectedRecent }) { selectedRecent = nil }
        }
    }

    private var welcome: some View {
        ContentUnavailableView {
            VStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                Text("Disc Image Studio").font(.largeTitle.weight(.semibold))
            }
        } description: {
            Text("Create artwork for CD, DVD and Blu-ray discs.\nStart a new project, open a file, or select a recent project.")
        } actions: {
            HStack(spacing: 12) {
                newProjectMenu
                    .buttonStyle(.borderedProminent)
                Button("Open Project…") { model.presentOpenProjectPanel() }
                    .buttonStyle(.bordered)
            }
            SettingsLink { Text("Settings…") }
                .buttonStyle(.bordered)
                .fixedSize()
                .padding(.top, 8)
        }
    }

    private var newProjectMenu: some View {
        Menu {
            ForEach(DiscFamily.allCases) { family in
                Button("\(family.label) Project…") { model.presentNewProject(family: family) }
            }
        } label: {
            Label("New Project…", systemImage: "plus")
        } primaryAction: {
            model.presentNewProject()
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Label(model.cliDetection.hasPrefix("Not found") ? "Engine not found" : "Engine ready",
                  systemImage: model.cliDetection.hasPrefix("Not found") ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .help(model.cliDetection)
            HStack {
                SettingsLink { Label("Settings…", systemImage: "gearshape") }
                Spacer()
                Menu {
                    Button("Clear Recent Projects", role: .destructive) {
                        model.clearRecents()
                        selectedRecent = nil
                    }
                    .disabled(model.recentProjects.isEmpty)
                    Divider()
                    Button("About Disc Image Studio") { model.presentAbout() }
                    Link("Upstream Project", destination: URL(string: "https://github.com/JiaFeiMiao-K-Cat/DiscImageStudio")!)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Recent projects and app information")
            }
            Text("GPL-3.0-or-later").font(.caption).foregroundStyle(.secondary)
        }
        .padding([.horizontal, .bottom])
    }

    private func project(for ids: Set<String>) -> RecentProject? {
        filteredRecents.first { ids.contains($0.id) }
    }

    private func reveal(_ entry: RecentProject) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    private func remove(_ entry: RecentProject) {
        model.removeRecent(entry)
        if selectedRecent == entry.id { selectedRecent = nil }
    }
}

/// Read-only information about a recent file; selecting it never changes the active project.
private struct RecentProjectDetail: View {
    let entry: RecentProject
    let open: () -> Void
    let reveal: () -> Void
    let remove: () -> Void
    @ViewState private var document: ProjectDocument?
    @ViewState private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 24) {
                    DiscThumbnail(base64: document?.thumbnailPngBase64 ?? entry.thumbnailPngBase64, size: 112)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(document?.name ?? entry.name).font(.largeTitle).textSelection(.enabled)
                        Label(entry.family.label, systemImage: entry.family.systemImage)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Project") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Location") { path(entry.url.path) }
                        LabeledContent("Last opened") {
                            Text(entry.lastOpenedUtc, format: .dateTime.year().month().day().hour().minute())
                        }
                        if let document {
                            LabeledContent("Layers", value: document.layers.count.formatted())
                        }
                    }
                    .padding(8)
                }

                if let document {
                    GroupBox("Output") {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("File") { path(document.outputs.outputPath) }
                            LabeledContent("Status", value: outputExists ? "File available" : "File not found")
                            LabeledContent("Sectors", value: (document.geometry.usableSectors ?? document.geometry.sectors).formatted())
                            if entry.family == .cd {
                                LabeledContent("CUE sheet", value: document.outputs.writeCue ? "Enabled" : "Disabled")
                            }
                        }
                        .padding(8)
                    }
                } else if let loadError {
                    Label {
                        Text("Output information is unavailable. \(loadError)")
                            .textSelection(.enabled)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView("Reading project…").controlSize(.small)
                }

                HStack(spacing: 12) {
                    Button("Open Project", action: open)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    Button("Show in Finder", action: reveal)
                    Spacer()
                    Button("Remove from Recents", role: .destructive, action: remove)
                        .help("Remove this entry from the list. The project file is kept.")
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .task(id: entry.id) {
            document = nil
            loadError = nil
            let accessed = entry.url.startAccessingSecurityScopedResource()
            defer { if accessed { entry.url.stopAccessingSecurityScopedResource() } }
            do {
                document = try ProjectStore.load(from: entry.url)
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private var outputExists: Bool {
        guard let document else { return false }
        return FileManager.default.fileExists(atPath: (document.outputs.outputPath as NSString).expandingTildeInPath)
    }

    private func path(_ value: String) -> some View {
        Text(value)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .multilineTextAlignment(.trailing)
            .lineLimit(3)
            .truncationMode(.middle)
            .help(value)
    }
}
