import AppKit
import DiscImageStudioKit
import UniformTypeIdentifiers
import SwiftUI

struct CalibrationView: View {
    @ObservedObject var model: WorkspaceViewModel
    @ObservedObject private var calibration: CalibrationViewModel
    @State private var canvasMode: CanvasMode = .photo
    @State private var outputPath = ""

    init(model: WorkspaceViewModel) {
        self.model = model
        _calibration = ObservedObject(wrappedValue: model.calibration)
    }

    private enum CanvasMode: String, CaseIterable, Identifiable {
        case photo
        case rectified

        var id: String { rawValue }
        var title: String { self == .photo ? "Photo" : "Rectified" }
    }

    var body: some View {
        HSplitView {
            leftColumn
                .frame(minWidth: 300, idealWidth: 335, maxWidth: 380)
            canvasColumn
                .frame(minWidth: 400, maxWidth: .infinity, minHeight: 420)
            resultColumn
                .frame(minWidth: 280, idealWidth: 310, maxWidth: 360)
        }
        .padding(12)
        .onAppear {
            if let state = model.state {
                calibration.configure(
                    from: state,
                    projectURL: model.projectURL,
                    customCLIPath: model.settings.cliPath
                )
            }
        }
        .onChange(of: model.projectURL) { _, _ in
            if let state = model.state {
                calibration.configure(
                    from: state,
                    projectURL: model.projectURL,
                    customCLIPath: model.settings.cliPath,
                    force: true
                )
            }
        }
        .onChange(of: calibration.isRectified) { _, ready in
            if ready { canvasMode = .rectified }
        }
    }

    // MARK: - Left column

    private var leftColumn: some View {
        ScrollView {
            VStack(spacing: 12) {
                stageCard
                setupCard
                targetCard
                photoCard
                measurementCard
            }
            .padding(.trailing, 2)
        }
    }

    private var stageCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Stage", subtitle: "Target type to burn next", icon: "ruler")
                Picker("", selection: Binding(
                    get: { calibration.stage },
                    set: { calibration.selectStage($0) }
                )) {
                    ForEach(CalibrationStage.allCases) { stage in
                        Text(stage.title).tag(stage)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(calibration.stage.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Text("Boundary and fine targets use the upstream Core fitters. Coarse targets are not exposed yet; start with boundary/fine if you already have a good initial radius.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var setupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(title: "Setup", subtitle: "Recorded with the target", icon: "slider.horizontal.3")
                    Spacer()
                    FamilyBadge(family: calibration.family, compact: true)
                }
                HStack(spacing: 10) {
                    calibrationNumberField("Inner radius (mm)", value: $calibration.geometry.innerRadiusMm)
                    calibrationNumberField("Outer radius (mm)", value: $calibration.geometry.outerRadiusMm)
                }
                HStack(spacing: 10) {
                    LabeledValue(label: "Sectors", value: calibration.geometry.sectors.formatted())
                    LabeledValue(
                        label: "Usable",
                        value: calibration.geometry.usableSectors?.formatted() ?? "Full"
                    )
                }
                DisclosureGroup("Track pitch coefficients") {
                    HStack(spacing: 10) {
                        calibrationNumberField("Linear", value: $calibration.geometry.pitchLinear)
                        calibrationNumberField("Quadratic", value: $calibration.geometry.pitchQuadratic)
                    }
                    calibrationNumberField("Cubic", value: $calibration.geometry.pitchCubic)
                }
                .font(.system(size: 10.5))
                .disabled(calibration.targetInfo != nil)
                if calibration.targetInfo != nil {
                    Text("This target is a frozen snapshot. Clear it before changing the setup.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
                Button {
                    calibration.createTarget()
                } label: {
                    Label(calibration.targetInfo == nil ? "Create target" : "Recreate target", systemImage: "scope")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!calibration.canCreateTarget)
            }
        }
    }

    private var targetCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(title: "Target", subtitle: "Burn, photograph, measure", icon: "target")
                    Spacer()
                    if calibration.targetInfo != nil {
                        Tag(text: calibration.stage.title.uppercased(), color: Theme.mint)
                    }
                }
                if let info = calibration.targetInfo {
                    LabeledValue(label: "Target id", value: String(info.targetId.prefix(12)) + "…", monospaced: true)
                    LabeledValue(
                        label: "Drawing annulus",
                        value: String(format: "%.2f–%.2f mm", info.drawingInnerRadiusMm, info.drawingOuterRadiusMm)
                    )
                    HStack(spacing: 8) {
                        Button {
                            chooseTargetOutput()
                        } label: {
                            Label("Generate burn image…", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        Button("Clear") { calibration.clearTarget() }
                            .buttonStyle(SecondaryActionButtonStyle())
                    }
                    if let artifact = calibration.generatedArtifactURL {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(artifact.lastPathComponent)
                                .font(.system(size: 10, weight: .semibold))
                            Text(artifact.path)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button {
                                model.useBurnArtifact(artifact)
                            } label: {
                                Label("Open in Burn workspace", systemImage: "opticaldiscdrive")
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                    }
                    Text("Use only blank media. Burn the generated WAV/ISO from the Burn workspace, then photograph the disc with the whole outer edge and center hole visible.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No target yet. Create one above.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var photoCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Photo", subtitle: "Rectify before measuring", icon: "camera")
                if calibration.targetInfo == nil {
                    Text("Create a target first.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } else {
                    HStack(spacing: 8) {
                        Button {
                            choosePhoto()
                        } label: {
                            Label(calibration.hasPhoto ? "Replace photo…" : "Import photo…", systemImage: "photo.badge.plus")
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        if calibration.hasPhoto {
                            Button("Suggest points") { calibration.suggestPhotoPoints() }
                                .buttonStyle(.plain)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.accent)
                        }
                    }

                    if calibration.hasPhoto {
                        HStack {
                            Text("Disc size")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $calibration.physicalDiscRadiusMm) {
                                Text("12 cm").tag(60.0)
                                Text("8 cm").tag(40.0)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 130)
                        }
                        Picker("", selection: $calibration.photoPointMode) {
                            ForEach(CalibrationPhotoPointMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        Text("Outer \(calibration.outerPoints.count) · Hole \(calibration.holePoints.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("Undo point") { calibration.removeLastPhotoPoint() }
                                .buttonStyle(SecondaryActionButtonStyle())
                            Button("Clear edge") { calibration.clearPhotoPoints() }
                                .buttonStyle(SecondaryActionButtonStyle())
                        }
                        Button {
                            calibration.rectify()
                        } label: {
                            Label("Calculate rectification", systemImage: "perspective")
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .disabled(calibration.isBusy)
                        if !calibration.rectificationMessage.isEmpty {
                            Text(calibration.rectificationMessage)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.mint)
                        }
                    }
                }
            }
        }
    }

    private var measurementCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Measurement", subtitle: calibration.stage.title, icon: "scribble.variable")
                if calibration.isRectified {
                    Text(calibration.stage.instructions)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("Points")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(calibration.measurementCount)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    if calibration.stage == .boundary {
                        HStack(spacing: 8) {
                            Button("New segment") { calibration.newBoundarySegment() }
                                .buttonStyle(SecondaryActionButtonStyle())
                            Text("\(calibration.boundarySegments.filter { !$0.isEmpty }.count) visible")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Search ± mm")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("", value: $calibration.radiusRangeMm, format: .number.precision(.fractionLength(0...3)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 76)
                        }
                        Toggle("Fit cubic pitch", isOn: $calibration.fitPitch)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 10))
                    }
                    HStack(spacing: 8) {
                        Button("Undo") { calibration.removeLastMeasurementPoint() }
                            .buttonStyle(SecondaryActionButtonStyle())
                        Button("Clear") { calibration.clearMeasurements() }
                            .buttonStyle(SecondaryActionButtonStyle())
                        Spacer()
                        Button {
                            calibration.solve()
                        } label: {
                            Label("Solve", systemImage: "function")
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .disabled(!calibration.canSolve || calibration.isBusy)
                    }
                } else {
                    Text("Rectify a photo to start measuring.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Center canvas

    private var canvasColumn: some View {
        VStack(spacing: 10) {
            HStack {
                SectionTitle(
                    title: canvasTitle,
                    subtitle: canvasSubtitle,
                    icon: canvasMode == .rectified ? "ruler" : "photo"
                )
                Spacer()
                if calibration.photoImage != nil && calibration.rectifiedImage != nil {
                    Picker("", selection: $canvasMode) {
                        ForEach(CanvasMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
            }
            .padding(.horizontal, 2)

            Group {
                if canvasMode == .rectified, let image = calibration.rectifiedImage {
                    CalibrationCanvas(
                        image: image,
                        tracePoints: calibration.tracePoints,
                        boundarySegments: calibration.boundarySegments,
                        showMeasurements: true,
                        onAdd: { calibration.addMeasurementPoint($0) }
                    )
                } else if let image = calibration.photoImage {
                    CalibrationCanvas(
                        image: image,
                        outerPoints: calibration.outerPoints,
                        holePoints: calibration.holePoints,
                        onAdd: { calibration.addPhotoPoint($0) }
                    )
                } else if let target = calibration.targetPreview {
                    VStack(spacing: 10) {
                        Image(decorative: target, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .padding(22)
                        Text("Target preview · import a photo after burning it")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                            .fill(Color.black.opacity(0.22))
                    )
                } else {
                    EmptyStateView(
                        icon: "ruler",
                        title: "No target",
                        message: "Create a boundary or fine target, burn it, then import a photo here.",
                        actionTitle: nil,
                        action: nil
                    )
                }
            }
        }
    }

    private var canvasTitle: String {
        if canvasMode == .rectified { return "Rectified disc" }
        return calibration.hasPhoto ? "Calibration photo" : "Target preview"
    }

    private var canvasSubtitle: String {
        if canvasMode == .rectified {
            return "Click along the \(calibration.stage == .fine ? "cross arm" : "black/white boundary")"
        }
        if calibration.hasPhoto {
            return "Place \(calibration.photoPointMode.title.lowercased()) points"
        }
        return "Physical target artwork"
    }

    // MARK: - Result column

    private var resultColumn: some View {
        ScrollView {
            VStack(spacing: 12) {
                statusCard
                resultCard
                workflowCard
            }
            .padding(.leading, 2)
        }
    }

    private var statusCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Calibration status", systemImage: calibration.isBusy ? "hourglass" : "checkmark.seal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(calibration.errorMessage == nil ? Theme.accent : Theme.amber)
                    Spacer()
                    if calibration.isBusy { ProgressView().controlSize(.small) }
                }
                Text(calibration.status)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = calibration.errorMessage {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var resultCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Fit result", subtitle: "Review before applying", icon: "function")
                if let result = calibration.solveResult {
                    HStack(spacing: 6) {
                        Tag(text: result.succeeded ? "FIT OK" : "NO FIT", color: result.succeeded ? Theme.mint : Theme.amber)
                        Tag(text: "RMS \(String(format: "%.3f", result.rmsErrorMm)) mm", color: .secondary)
                        if result.boundaryLimited { Tag(text: "EDGE", color: Theme.amber) }
                    }
                    if let best = result.best {
                        Divider().opacity(0.5)
                        LabeledValue(label: "Inner radius", value: String(format: "%.5f mm", best.innerRadiusMm))
                        LabeledValue(label: "Outer radius", value: String(format: "%.5f mm", best.outerRadiusMm))
                        LabeledValue(label: "Pitch", value: String(
                            format: "%.6g / %.6g / %.6g",
                            best.pitchLinear,
                            best.pitchQuadratic,
                            best.pitchCubic
                        ))
                        LabeledValue(label: "Rotation", value: String(format: "%.2f°", result.rotationRadians * 180 / .pi))
                        LabeledValue(label: "Candidates", value: "\(result.candidates.count)")
                    }
                    if !result.warnings.isEmpty {
                        Divider().opacity(0.5)
                        ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, warning in
                            Text("• \(warning)")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Theme.amber)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button {
                        calibration.applyBest(to: model)
                    } label: {
                        Label("Apply to project", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(!result.succeeded || result.best == nil || calibration.isBusy)
                    Text("Applying updates the project's inner/outer radius and pitch coefficients. The burned target's original geometry stays frozen in the session.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if calibration.isRectified {
                    Text("Trace the target and press Solve. The engine will search the track model around the captured geometry.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Create a target, burn it, photograph it, then rectify the photo.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var workflowCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Workflow", systemImage: "list.number")
                    .font(.system(size: 11, weight: .semibold))
                WorkflowStep(number: 1, title: "Create", detail: "Generate the target preview and encoding image.")
                WorkflowStep(number: 2, title: "Burn", detail: "Write the WAV/ISO to a blank disc from the Burn workspace.")
                WorkflowStep(number: 3, title: "Photograph", detail: "Keep the whole outer edge and the center hole visible.")
                WorkflowStep(number: 4, title: "Rectify & trace", detail: "Mark the physical edges, rectify, then follow one boundary/arm.")
                WorkflowStep(number: 5, title: "Apply", detail: "Use the fitted radii and cubic pitch for the next target or project.")
            }
        }
    }

    private func calibrationNumberField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number.precision(.fractionLength(0...7)))
                .textFieldStyle(.roundedBorder)
                .disabled(calibration.targetInfo != nil)
        }
    }

    // MARK: - Actions

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .bmp, .gif]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose the photo of the burned calibration disc"
        if panel.runModal() == .OK, let url = panel.url {
            calibration.importPhoto(at: url)
            canvasMode = .photo
        }
    }

    private func chooseTargetOutput() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "calibration-\(calibration.stage.rawValue).\(calibration.family.defaultOutputExtension)"
        panel.directoryURL = model.settings.defaultProjectsURL
        if calibration.family == .cd {
            panel.allowedContentTypes = [UTType(filenameExtension: "wav") ?? .audio]
        } else {
            panel.allowedContentTypes = [UTType(filenameExtension: "iso") ?? .data]
        }
        panel.title = "Choose the calibration artifact"
        if panel.runModal() == .OK, let url = panel.url {
            calibration.generateTargetArtifact(to: url)
        }
    }
}

private struct WorkflowStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
