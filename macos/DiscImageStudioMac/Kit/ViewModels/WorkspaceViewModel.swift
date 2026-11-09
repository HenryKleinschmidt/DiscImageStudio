import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

public enum Workspace: String, CaseIterable, Identifiable, Sendable {
    case design
    case preview
    case export
    case calibration
    case burn

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .design: return "Design"
        case .preview: return "Preview"
        case .export: return "Export"
        case .calibration: return "Calibrate"
        case .burn: return "Burn"
        }
    }

    public var subtitle: String {
        switch self {
        case .design: return "Compose layers and tone"
        case .preview: return "Check the disc projection"
        case .export: return "Write the disc image"
        case .calibration: return "Measure a burned target"
        case .burn: return "Write to optical media"
        }
    }

    public var systemImage: String {
        switch self {
        case .design: return "square.3.layers.3d"
        case .preview: return "eye"
        case .export: return "arrow.down.circle"
        case .calibration: return "ruler"
        case .burn: return "opticaldiscdrive"
        }
    }
}

public enum PreviewMode: String, CaseIterable, Identifiable, Sendable {
    case design
    case readback

    public var id: String { rawValue }
    public var title: String { self == .design ? "Design projection" : "Artifact read-back" }
}

public struct AppAlert: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

private struct RenderedImages: @unchecked Sendable {
    let composite: CGImage?
    let tone: CGImage?
}

@MainActor
public final class WorkspaceViewModel: ObservableObject {
    public let settings: AppSettings
    public let calibration = CalibrationViewModel()
    private let cliService: CLIService
    private let recentStore: RecentProjectsStore
    private let sessionDirectory: URL
    private var designTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var designRevision = 0

    @Published public var workspace: Workspace = .design
    @Published public private(set) var state: ProjectState?
    @Published public private(set) var projectURL: URL?
    @Published public private(set) var isDirty = false
    @Published public var selectedLayerID: String?
    @Published public private(set) var designComposite: CGImage?
    @Published public private(set) var tonePreview: CGImage?
    @Published public private(set) var previewImage: CGImage?
    @Published public var previewMode: PreviewMode = .design
    @Published public var previewSize: Int = 1600
    @Published public var previewMeasuredInnerRadiusMm: Double = 24.5
    @Published public var previewMeasuredOuterRadiusMm: Double = 56.8
    @Published public private(set) var previewStatus = "Render a preview to inspect the engine's projection."
    @Published public private(set) var isPreviewing = false
    @Published public private(set) var isExporting = false
    @Published public private(set) var exportLog = ""
    @Published public private(set) var exportStatus = "Ready when the design has at least one layer."
    @Published public private(set) var lastOutputURL: URL?
    @Published public private(set) var recentProjects: [RecentProject] = []
    @Published public var alert: AppAlert?
    @Published public private(set) var cliDetection = "Checking…"
    @Published public private(set) var layerAspects: [String: CGSize] = [:]
    @Published public private(set) var burnArtifactOverride: URL?
    @Published public var isNewProjectPresented = false
    @Published public var newProjectFamily: DiscFamily = .cd
    @Published public var isProjectSettingsPresented = false
    @Published public var isAboutPresented = false

    public init(
        settings: AppSettings? = nil,
        cliService: CLIService = .shared,
        recentStore: RecentProjectsStore = RecentProjectsStore()
    ) {
        let settings = settings ?? AppSettings()
        self.settings = settings
        self.cliService = cliService
        self.recentStore = recentStore
        self.previewSize = settings.previewSize
        self.sessionDirectory = AppPaths.caches
            .appendingPathComponent("Session-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString.prefix(8))")
        recentProjects = recentStore.load()
        cliDetection = cliService.detectionSummary(customPath: settings.cliPath)
    }

    // MARK: - Presentation

    public func presentNewProject(family: DiscFamily = .cd) {
        newProjectFamily = family
        isNewProjectPresented = true
    }

    public func presentOpenProjectPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "discproj") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Open a Disc Image Studio project"
        if panel.runModal() == .OK, let url = panel.url {
            openProject(at: url)
        }
    }

    public func presentSaveAsPanel() {
        guard let state else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "discproj") ?? .data]
        panel.nameFieldStringValue = state.name + ".discproj"
        panel.directoryURL = projectURL?.deletingLastPathComponent() ?? settings.defaultProjectsURL
        panel.title = "Save project as"
        if panel.runModal() == .OK, let url = panel.url {
            saveProjectAs(at: url)
        }
    }

    public func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .bmp, .gif, .tiff, .heic]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.title = "Import images for the disc design"
        if panel.runModal() == .OK {
            importImages(from: panel.urls)
        }
    }

    public func chooseDataDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose files to place on the disc"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    public func chooseOutputPath(family: DiscFamily) -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (state?.name ?? "disc-image") + "." + family.defaultOutputExtension
        if family == .cd {
            panel.allowedContentTypes = [UTType(filenameExtension: "wav") ?? .audio, UTType(filenameExtension: "raw") ?? .data]
        } else {
            panel.allowedContentTypes = [UTType(filenameExtension: "iso") ?? .data]
        }
        panel.directoryURL = settings.defaultProjectsURL
        panel.title = "Choose the generated \(family.label) output"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    public func presentAbout() {
        isAboutPresented = true
    }

    // MARK: - Derived state

    public var hasProject: Bool { state != nil }

    public var family: DiscFamily { state?.family ?? .cd }

    public var canExport: Bool {
        guard let state, !state.layers.isEmpty else { return false }
        return cliService.locateCLI(customPath: settings.cliPath) != nil
    }

    public var selectedLayer: ProjectLayer? {
        guard let selectedLayerID else { return nil }
        return state?.layers.first { $0.id == selectedLayerID }
    }

    public var projectDisplayName: String {
        state?.name ?? "Disc Image Studio"
    }

    public var windowSubtitle: String {
        guard let projectURL else { return "" }
        return projectURL.deletingLastPathComponent().path
    }

    public var outputDisplayName: String {
        guard let path = state?.outputs.outputPath, !path.isEmpty else { return "No output chosen" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    public var statusBadge: String {
        guard let state else { return "" }
        return "\(state.family.label) · \(state.layers.count) layer\(state.layers.count == 1 ? "" : "s")"
    }

    public var selectedLayerAspectRatio: Double? {
        guard let selectedLayer, let size = layerAspects[selectedLayer.id], size.height > 0 else { return nil }
        return size.width / size.height
    }

    public func refreshCLIDetection() {
        cliDetection = cliService.detectionSummary(customPath: settings.cliPath)
    }

    // MARK: - Bindings

    public func projectBinding<Value>(
        _ keyPath: WritableKeyPath<ProjectState, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { self.state?[keyPath: keyPath] ?? fallback },
            set: { [weak self] newValue in
                self?.apply { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    public func layerBinding<Value>(
        _ layerID: String,
        _ keyPath: WritableKeyPath<ProjectLayer, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                self.state?.layers.first(where: { $0.id == layerID })?[keyPath: keyPath] ?? fallback
            },
            set: { [weak self] newValue in
                self?.updateLayer(layerID) { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    public func apply(_ mutation: (inout ProjectState) -> Void) {
        guard var updated = state else { return }
        let before = updated
        mutation(&updated)
        // SwiftUI can write a binding back with the same value when a view is
        // rebuilt (for example when switching workspaces). Do not mark a clean
        // project dirty or schedule a render for a no-op.
        guard updated != before else { return }
        updated.modifiedUtc = Date()
        state = updated
        isDirty = true
        scheduleDesignRender()
    }

    public func updateLayer(_ id: String, _ mutation: (inout ProjectLayer) -> Void) {
        apply { state in
            guard let index = state.layers.firstIndex(where: { $0.id == id }) else { return }
            mutation(&state.layers[index])
        }
    }

    // MARK: - Project lifecycle

    public func createProject(
        name: String,
        family: DiscFamily,
        geometry: ProjectGeometry,
        invertMapping: Bool,
        projectURL: URL,
        outputURL: URL,
        dataDirectory: String = ""
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectValidationError.invalidProject("Give the project a name.")
        }
        try geometry.validate(family: family)
        let label = family == .bd ? "BD_IMAGE" : (family == .dvd ? "DVD_IMAGE" : "CD_IMAGE")
        let outputs = ProjectOutputs(
            outputPath: outputURL.path,
            writeCue: true,
            dataDirectory: dataDirectory,
            volumeLabel: label,
            interleave: true,
            filesAtOuterRing: false,
            dvdReadCompatibility: false
        )
        let newState = ProjectState(
            name: trimmed,
            family: family,
            geometry: geometry,
            layers: [],
            outputs: outputs,
            tone: .photo,
            invertMapping: invertMapping
        )
        state = newState
        self.projectURL = projectURL
        isDirty = true
        selectedLayerID = nil
        designComposite = nil
        tonePreview = nil
        previewImage = nil
        previewMode = .design
        previewMeasuredInnerRadiusMm = geometry.innerRadiusMm
        previewMeasuredOuterRadiusMm = geometry.contentOuterRadiusMm(family: family)
        workspace = .design
        if !saveProject() {
            return
        }
        refreshCLIDetection()
    }

    public func openProject(at url: URL) {
        do {
            let document = try ProjectStore.load(from: url)
            let opened = ProjectState(document: document)
            state = opened
            projectURL = url
            isDirty = false
            selectedLayerID = opened.layers.first?.id
            designComposite = nil
            tonePreview = nil
            previewImage = nil
            previewStatus = "Render a preview to inspect the engine's projection."
            previewMode = .design
            previewMeasuredInnerRadiusMm = opened.geometry.innerRadiusMm
            previewMeasuredOuterRadiusMm = opened.contentOuterRadiusMm
            workspace = .design
            refreshLayerAspects()
            recordRecent(opened, url: url)
            scheduleDesignRender(immediately: true)
        } catch {
            present(error, title: "Could not open project")
        }
    }

    @discardableResult
    public func saveProject() -> Bool {
        guard let state, let projectURL else {
            alert = AppAlert(title: "No project file", message: "Create or open a project before saving.")
            return false
        }
        do {
            var saved = state
            saved.thumbnailPngBase64 = DesignRenderer.thumbnailBase64(
                layers: saved.layers,
                outerRadiusMm: saved.contentOuterRadiusMm
            )
            saved.modifiedUtc = Date()
            try ProjectStore.save(saved.document(), to: projectURL)
            self.state = saved
            isDirty = false
            recordRecent(saved, url: projectURL)
            return true
        } catch {
            present(error, title: "Could not save project")
            return false
        }
    }

    public func saveProjectAs(at url: URL) {
        guard var state else { return }
        do {
            state.thumbnailPngBase64 = DesignRenderer.thumbnailBase64(
                layers: state.layers,
                outerRadiusMm: state.contentOuterRadiusMm
            )
            state.modifiedUtc = Date()
            try ProjectStore.save(state.document(), to: url)
            self.state = state
            projectURL = url
            isDirty = false
            recordRecent(state, url: url)
        } catch {
            present(error, title: "Could not save project")
        }
    }

    public func closeProject() {
        if isDirty && !saveProject() { return }
        designTask?.cancel()
        previewTask?.cancel()
        state = nil
        projectURL = nil
        isDirty = false
        selectedLayerID = nil
        designComposite = nil
        tonePreview = nil
        previewImage = nil
        exportLog = ""
        lastOutputURL = nil
        workspace = .design
    }

    public func applyProjectSettings(
        name: String,
        geometry: ProjectGeometry,
        invertMapping: Bool
    ) throws {
        guard var updated = state else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectValidationError.invalidProject("Give the project a name.")
        }
        try geometry.validate(family: updated.family)
        updated.name = trimmed
        updated.geometry = geometry
        updated.invertMapping = invertMapping
        updated.modifiedUtc = Date()
        state = updated
        isDirty = true
        previewMeasuredInnerRadiusMm = geometry.innerRadiusMm
        previewMeasuredOuterRadiusMm = geometry.contentOuterRadiusMm(family: updated.family)
        previewImage = nil
        scheduleDesignRender(immediately: true)
    }

    public func removeRecent(_ entry: RecentProject) {
        recentStore.remove(path: entry.projectPath)
        recentProjects = recentStore.load()
    }

    public func clearRecents() {
        recentStore.clear()
        recentProjects = []
    }

    public func notePreviewSizeChanged() {
        settings.previewSize = previewSize
    }

    public func useBurnArtifact(_ url: URL?) {
        burnArtifactOverride = url
        if url != nil {
            workspace = .burn
        }
    }

    private func recordRecent(_ state: ProjectState, url: URL) {
        let entry = RecentProject(
            name: state.name,
            discFamily: ProjectDocument.familyCode(for: state.family),
            projectPath: url.path,
            thumbnailPngBase64: state.thumbnailPngBase64,
            lastOpenedUtc: Date()
        )
        recentStore.record(entry)
        recentProjects = recentStore.load()
    }

    // MARK: - Layers

    public func importImages(from urls: [URL]) {
        guard var updated = state else { return }
        var imported: [ProjectLayer] = []
        var failures: [String] = []
        for url in urls {
            guard let size = DesignRenderer.imagePixelSize(at: url.path) else {
                failures.append(url.lastPathComponent)
                continue
            }
            let layer = ProjectLayer(name: url.lastPathComponent, imagePath: url.path)
            layerAspects[layer.id] = size
            imported.append(layer)
        }
        guard !imported.isEmpty else {
            if !failures.isEmpty {
                alert = AppAlert(
                    title: "Images could not be imported",
                    message: failures.joined(separator: "\n")
                )
            }
            return
        }
        updated.layers.insert(contentsOf: imported, at: 0)
        updated.modifiedUtc = Date()
        state = updated
        selectedLayerID = imported.first?.id
        isDirty = true
        if !failures.isEmpty {
            alert = AppAlert(
                title: "Some images were skipped",
                message: failures.joined(separator: "\n")
            )
        }
        scheduleDesignRender(immediately: true)
    }

    public func removeSelectedLayer() {
        guard let selectedLayerID else { return }
        apply { state in
            state.layers.removeAll { $0.id == selectedLayerID }
        }
        layerAspects.removeValue(forKey: selectedLayerID)
        self.selectedLayerID = state?.layers.first?.id
    }

    public func toggleVisibility(_ layerID: String) {
        updateLayer(layerID) { $0.visible.toggle() }
    }

    public func moveLayers(fromOffsets: IndexSet, toOffset: Int) {
        guard var updated = state else { return }
        let moving = fromOffsets.map { updated.layers[$0] }
        for index in fromOffsets.sorted(by: >) {
            updated.layers.remove(at: index)
        }
        let removedBefore = fromOffsets.filter { $0 < toOffset }.count
        let destination = max(0, min(updated.layers.count, toOffset - removedBefore))
        updated.layers.insert(contentsOf: moving, at: destination)
        updated.modifiedUtc = Date()
        state = updated
        isDirty = true
        scheduleDesignRender(immediately: true)
    }

    public func moveLayer(_ layerID: String, before targetID: String?) {
        guard var updated = state,
              let from = updated.layers.firstIndex(where: { $0.id == layerID })
        else { return }
        let layer = updated.layers.remove(at: from)
        if let targetID, let target = updated.layers.firstIndex(where: { $0.id == targetID }) {
            updated.layers.insert(layer, at: target)
        } else {
            updated.layers.append(layer)
        }
        updated.modifiedUtc = Date()
        state = updated
        isDirty = true
        selectedLayerID = layerID
        scheduleDesignRender(immediately: true)
    }

    public func refreshLayerAspects() {
        guard let state else {
            layerAspects = [:]
            return
        }
        var aspects: [String: CGSize] = [:]
        for layer in state.layers {
            if let existing = layerAspects[layer.id] {
                aspects[layer.id] = existing
            } else if let size = DesignRenderer.imagePixelSize(at: layer.imagePath) {
                aspects[layer.id] = size
            }
        }
        layerAspects = aspects
    }

    // MARK: - Native design rendering

    public func scheduleDesignRender(immediately: Bool = false) {
        designTask?.cancel()
        designRevision += 1
        let revision = designRevision
        guard let snapshot = state else { return }
        designTask = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(nanoseconds: 280_000_000)
            }
            guard !Task.isCancelled, let self, self.designRevision == revision else { return }
            let rendered = await Task.detached(priority: .userInitiated) { () -> RenderedImages in
                let composite = try? DesignRenderer.renderComposite(
                    layers: snapshot.layers,
                    outerRadiusMm: snapshot.contentOuterRadiusMm,
                    outputSize: 1400
                )
                var tone: CGImage?
                if let composite {
                    tone = try? DesignRenderer.renderDiscPreview(
                        composite: composite,
                        family: snapshot.family,
                        geometry: snapshot.geometry,
                        tone: snapshot.tone,
                        invertMapping: snapshot.invertMapping,
                        size: 640
                    )
                }
                return RenderedImages(composite: composite, tone: tone)
            }.value
            guard !Task.isCancelled, self.designRevision == revision else { return }
            self.designComposite = rendered.composite
            self.tonePreview = rendered.tone
        }
    }

    private func compositeCacheURL(name: String) throws -> URL {
        try AppPaths.ensureDirectory(sessionDirectory)
        return sessionDirectory.appendingPathComponent(name)
    }

    private func renderCompositeFile(
        snapshot: ProjectState,
        size: Int,
        name: String
    ) async throws -> URL {
        guard !snapshot.layers.isEmpty else {
            throw ProjectValidationError.invalidProject("Import at least one image on the Design page first.")
        }
        let url = try compositeCacheURL(name: name)
        let outer = snapshot.contentOuterRadiusMm
        try await Task.detached(priority: .userInitiated) {
            let image = try DesignRenderer.renderComposite(
                layers: snapshot.layers,
                outerRadiusMm: outer,
                outputSize: size
            )
            try DesignRenderer.writePNG(image, to: url)
        }.value
        return url
    }

    // MARK: - Preview

    public func renderPreviewIfNeeded() {
        if previewImage == nil && !isPreviewing {
            renderPreview()
        }
    }

    public func renderPreview() {
        previewTask?.cancel()
        guard let snapshot = state else { return }
        guard !snapshot.layers.isEmpty else {
            previewStatus = "Import an image on the Design page first."
            return
        }
        isPreviewing = true
        previewStatus = "Rendering the \(snapshot.family.label) projection…"
        let size = previewSize
        let mode = previewMode
        let measuredInner = previewMeasuredInnerRadiusMm
        let measuredOuter = previewMeasuredOuterRadiusMm

        previewTask = Task { [weak self] in
            guard let self else { return }
            do {
                if snapshot.family == .bd {
                    let compositeURL = try await self.renderCompositeFile(
                        snapshot: snapshot,
                        size: size,
                        name: "bd-preview-composite.png"
                    )
                    let image = try await Task.detached(priority: .userInitiated) { () -> CGImage in
                        guard let composite = DesignRenderer.loadImage(at: compositeURL.path, maxPixel: size) else {
                            throw DesignRenderError.cannotLoadImage(compositeURL.path)
                        }
                        return try DesignRenderer.renderDiscPreview(
                            composite: composite,
                            family: snapshot.family,
                            geometry: snapshot.geometry,
                            tone: snapshot.tone,
                            invertMapping: snapshot.invertMapping,
                            size: size
                        )
                    }.value
                    if Task.isCancelled { return }
                    self.previewImage = image
                    self.previewStatus = "Native BD-R projection · \(size) px · \(snapshot.tone.summary)"
                    self.isPreviewing = false
                    return
                }

                guard let invocation = self.cliService.locateCLI(customPath: self.settings.cliPath) else {
                    throw CLIError.notFound
                }
                let outputURL = try self.compositeCacheURL(name: "preview.png")
                try? FileManager.default.removeItem(at: outputURL)

                var arguments: [String]?
                if mode == .readback {
                    arguments = CLICommandBuilder.readbackArguments(
                        state: snapshot,
                        outputURL: outputURL,
                        size: size
                    )
                    if arguments == nil {
                        throw ProjectValidationError.invalidProject(
                            "Generate the \(snapshot.family.label) artifact first, or switch to Design projection."
                        )
                    }
                } else {
                    let compositeURL = try await self.renderCompositeFile(
                        snapshot: snapshot,
                        size: 4096,
                        name: "preview-composite.png"
                    )
                    arguments = try CLICommandBuilder.previewArguments(
                        state: snapshot,
                        compositeURL: compositeURL,
                        outputURL: outputURL,
                        size: size,
                        measuredInnerRadiusMm: measuredInner,
                        measuredOuterRadiusMm: measuredOuter
                    )
                }
                guard let arguments else {
                    throw ProjectValidationError.invalidProject("This preview mode is not available.")
                }
                self.previewStatus = "Running \(arguments.first ?? "preview")…"
                let result = try await self.cliService.run(invocation, arguments: arguments)
                guard FileManager.default.fileExists(atPath: outputURL.path) else {
                    throw CLIError.missingOutput(outputURL.path)
                }
                if let image = DesignRenderer.loadImage(at: outputURL.path, maxPixel: size) {
                    if Task.isCancelled { return }
                    self.previewImage = image
                    self.previewStatus = "\(mode.title) · \(size) px · \(String(format: "%.1f", result.duration))s"
                } else {
                    throw DesignRenderError.cannotLoadImage(outputURL.path)
                }
                self.isPreviewing = false
            } catch {
                if Task.isCancelled {
                    self.previewStatus = "Preview cancelled."
                } else {
                    self.previewStatus = error.localizedDescription
                    self.present(error, title: "Preview failed")
                }
                self.isPreviewing = false
            }
        }
    }

    // MARK: - Export

    public func generateImage() {
        exportTask?.cancel()
        guard let snapshot = state else { return }
        guard !snapshot.layers.isEmpty else {
            exportStatus = "Import an image on the Design page first."
            return
        }
        guard let invocation = cliService.locateCLI(customPath: settings.cliPath) else {
            alert = AppAlert(
                title: "Disc engine not found",
                message: CLIError.notFound.localizedDescription
            )
            return
        }
        guard saveProject() else { return }
        guard var saved = state else { return }
        saved.outputs.outputPath = (saved.outputs.outputPath as NSString).expandingTildeInPath
        state = saved
        isExporting = true
        exportLog = ""
        exportStatus = "Preparing the \(saved.family.label) engine…"
        lastOutputURL = nil
        previewTask?.cancel()

        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let compositeURL = try await self.renderCompositeFile(
                    snapshot: saved,
                    size: 8192,
                    name: "export-composite.png"
                )
                let arguments = try CLICommandBuilder.exportArguments(state: saved, compositeURL: compositeURL)
                self.exportLog = "$ \(invocation.displayName) \(arguments.joined(separator: " "))\n"
                self.exportStatus = "Generating \(saved.family.label) image…"
                let result = try await self.cliService.run(invocation, arguments: arguments) { chunk in
                    Task { @MainActor in
                        self.appendExportLog(chunk)
                    }
                }
                self.appendExportLog(result.combinedOutput)
                let outputURL = URL(fileURLWithPath: saved.outputs.outputPath)
                guard FileManager.default.fileExists(atPath: outputURL.path) else {
                    throw CLIError.missingOutput(outputURL.path)
                }
                self.lastOutputURL = outputURL
                self.exportStatus = "Finished in \(String(format: "%.1f", result.duration)) s · \(outputURL.lastPathComponent)"
                self.isExporting = false
            } catch {
                if Task.isCancelled {
                    self.exportStatus = "Generation cancelled."
                } else {
                    self.exportStatus = error.localizedDescription
                    self.present(error, title: "Generation failed")
                }
                self.isExporting = false
            }
        }
    }

    private func appendExportLog(_ text: String) {
        guard !text.isEmpty else { return }
        exportLog += text.hasSuffix("\n") ? text : text + "\n"
        if exportLog.count > 120_000 {
            exportLog = String(exportLog.suffix(90_000))
        }
    }

    public func cancelExport() {
        guard isExporting else { return }
        exportTask?.cancel()
        cliService.cancelCurrent()
        exportStatus = "Cancelling…"
    }

    public func revealOutput() {
        guard let lastOutputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastOutputURL])
    }

    public func revealProject() {
        guard let projectURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
    }

    // MARK: - Helpers

    public func present(_ error: Error, title: String) {
        alert = AppAlert(title: title, message: error.localizedDescription)
    }

    public func suggestedProjectURL(name: String) -> URL {
        let safe = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let base = safe.isEmpty ? "Untitled" : safe
        return settings.defaultProjectsURL.appendingPathComponent(base).appendingPathExtension("discproj")
    }

    public func suggestedOutputURL(name: String, family: DiscFamily) -> URL {
        let safe = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let base = safe.isEmpty ? "Untitled" : safe
        return settings.defaultProjectsURL
            .appendingPathComponent(base)
            .appendingPathExtension(family.defaultOutputExtension)
    }
}
