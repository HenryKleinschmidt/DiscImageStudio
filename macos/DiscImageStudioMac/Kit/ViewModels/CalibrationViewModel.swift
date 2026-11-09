import CoreGraphics
import Foundation

public enum CalibrationStage: String, CaseIterable, Identifiable, Codable, Sendable {
    case boundary
    case fine

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .boundary: return "Boundary"
        case .fine: return "Fine cross"
        }
    }
    public var subtitle: String {
        switch self {
        case .boundary: return "Trace the wavy black/white boundary"
        case .fine: return "Trace one radial cross arm"
        }
    }
    public var instructions: String {
        switch self {
        case .boundary:
            return "Trace the visible black/white boundary of the wavy-boundary target. At least 6 points covering 55% of the drawing radius, or 4–8 shorter segments."
        case .fine:
            return "Trace one clear cross arm from the inside out. At least 6 points spanning 18% of the drawing annulus; more points improve the fit."
        }
    }
}

public enum CalibrationPhotoPointMode: String, CaseIterable, Identifiable, Sendable {
    case outer
    case hole

    public var id: String { rawValue }
    public var title: String { self == .outer ? "Outer edge" : "Center hole" }
    public var color: String { self == .outer ? "cyan" : "orange" }
}

public struct CalibrationTargetInfo: Codable, Equatable, Sendable {
    public let targetId: String
    public let kind: String
    public let stage: String
    public let innerRadiusMm: Double
    public let outerRadiusMm: Double
    public let sectors: Int64
    public let usableSectors: Int64?
    public let pitchLinear: Double
    public let pitchQuadratic: Double
    public let pitchCubic: Double
    public let drawingInnerRadiusMm: Double
    public let drawingOuterRadiusMm: Double
    public let previewPath: String
    public let burnImagePath: String
    public let sessionPath: String
    public let previewSize: Int
    public let burnImageSize: Int
}

public struct CalibrationRectifyResult: Codable, Equatable, Sendable {
    public let succeeded: Bool
    public let message: String
    public let outerRmsPixels: Double
    public let holeRmsPixels: Double
    public let canvasOuterRadiusMm: Double
    public let pixelSize: Int
    public let output: String?
}

public struct CalibrationParametersDTO: Codable, Equatable, Sendable {
    public let kind: String
    public let innerRadiusMm: Double
    public let outerRadiusMm: Double
    public let sectors: Int64
    public let usableSectors: Int64?
    public let pitchLinear: Double
    public let pitchQuadratic: Double
    public let pitchCubic: Double
    public let invertMapping: Bool
}

public struct CalibrationCandidateDTO: Codable, Equatable, Sendable {
    public let parameters: CalibrationParametersDTO
    public let rotationRadians: Double
    public let rmsErrorMm: Double
    public let robustCost: Double
    public let maxErrorMm: Double
    public let outlierCount: Int
}

public struct CalibrationSolveResult: Codable, Equatable, Sendable {
    public let succeeded: Bool
    public let reliable: Bool
    public let boundaryLimited: Bool
    public let requiresShapeConfirmation: Bool
    public let rotationRadians: Double
    public let rmsErrorMm: Double
    public let warnings: [String]
    public let best: CalibrationParametersDTO?
    public let candidates: [CalibrationCandidateDTO]
}

private struct PixelPoint: Codable { let x: Double; let y: Double }
private struct PhotoPointsPayload: Codable { let outer: [PixelPoint]; let hole: [PixelPoint] }
private struct MMPoint: Codable { let x: Double; let y: Double }
private struct TracePayload: Codable { let armIndex: Int; let points: [MMPoint] }
private struct SegmentPayload: Codable { let id: Int; let points: [MMPoint] }
private struct SolvePayload: Codable {
    let traces: [TracePayload]?
    let segments: [SegmentPayload]?
    let radiusRangeMm: Double
    let fitPitch: Bool
    let autoRange: Bool
    let pitchCoefficientRange: Double
}

@MainActor
public final class CalibrationViewModel: ObservableObject {
    @Published public private(set) var family: DiscFamily = .dvd
    @Published public var geometry = DiscFamily.dvd.defaultGeometry
    @Published public var invertMapping = false
    @Published public var dvdReadCompatibility = false
    @Published public var stage: CalibrationStage = .fine
    @Published public private(set) var targetInfo: CalibrationTargetInfo?
    @Published public private(set) var targetPreview: CGImage?
    @Published public private(set) var burnImageURL: URL?
    @Published public private(set) var sessionURL: URL?
    @Published public private(set) var generatedArtifactURL: URL?
    @Published public private(set) var isBusy = false
    @Published public private(set) var status = "Choose a stage and create a target."
    @Published public private(set) var errorMessage: String?

    @Published public private(set) var photoURL: URL?
    @Published public private(set) var photoImage: CGImage?
    @Published public var photoPointMode: CalibrationPhotoPointMode = .outer
    @Published public private(set) var outerPoints: [CGPoint] = []
    @Published public private(set) var holePoints: [CGPoint] = []
    @Published public var physicalDiscRadiusMm = 60.0
    @Published public private(set) var rectifiedImage: CGImage?
    @Published public private(set) var rectifiedSize = 0
    @Published public private(set) var canvasOuterRadiusMm = 63.0
    @Published public private(set) var rectificationMessage = ""

    @Published public private(set) var tracePoints: [CGPoint] = []
    @Published public private(set) var boundarySegments: [[CGPoint]] = []
    @Published public var activeBoundarySegment = 0
    @Published public var radiusRangeMm = 0.02
    @Published public var fitPitch = true
    @Published public var autoRange = true
    @Published public private(set) var solveResult: CalibrationSolveResult?

    private let cliService: CLIService
    private var customCLIPath = ""
    private var configuredProjectURL: URL?
    private var workDirectory: URL?

    public init(cliService: CLIService = .shared) {
        self.cliService = cliService
    }

    public var canCreateTarget: Bool { !isBusy }
    public var isRectified: Bool { rectifiedImage != nil }
    public var hasPhoto: Bool { photoImage != nil }

    public var measurementCount: Int {
        if stage == .fine { return tracePoints.count }
        return boundarySegments.reduce(0) { $0 + $1.count }
    }

    public var canSolve: Bool {
        guard isRectified else { return false }
        if stage == .fine { return tracePoints.count >= 6 }
        return boundarySegments.contains { $0.count >= 3 }
    }

    public var bestParameters: CalibrationParametersDTO? {
        solveResult?.best
    }

    public func configure(
        from state: ProjectState,
        projectURL: URL?,
        customCLIPath: String,
        force: Bool = false
    ) {
        self.customCLIPath = customCLIPath
        guard force || configuredProjectURL != projectURL else { return }
        guard !isBusy else { return }
        configuredProjectURL = projectURL
        family = state.family
        geometry = state.geometry
        invertMapping = state.invertMapping
        dvdReadCompatibility = state.outputs.dvdReadCompatibility
        physicalDiscRadiusMm = state.geometry.outerRadiusMm <= 45 ? 40 : 60
        radiusRangeMm = stage == .boundary ? 0.01 : 0.02
        resetAll()
        status = "Choose a stage and create a target."
    }

    public func clearTarget() {
        guard !isBusy else { return }
        resetAll()
        status = "Target cleared. Create a new target from the current geometry."
    }

    public func selectStage(_ newStage: CalibrationStage) {
        guard newStage != stage else { return }
        stage = newStage
        radiusRangeMm = newStage == .boundary ? 0.01 : 0.02
        resetAll()
        status = newStage == .boundary
            ? "Create a wavy-boundary target, burn it, and photograph the result."
            : "Create a fine cross target, burn it, and photograph the result."
    }

    // MARK: - Target

    public func createTarget() {
        guard !isBusy else { return }
        do {
            let invocation = try requireCLI()
            let directory = try ensureWorkDirectory()
            let session = directory.appendingPathComponent("\(stage.rawValue).calibration.json")
            let preview = directory.appendingPathComponent("\(stage.rawValue)-preview.png")
            let burn = directory.appendingPathComponent("\(stage.rawValue)-burn.png")
            var args = [
                "calibration-create",
                "--kind", family.rawValue,
                "--stage", stage.rawValue,
                "--inner-radius", CLICommandBuilder.number(geometry.innerRadiusMm),
                "--outer-radius", CLICommandBuilder.number(geometry.outerRadiusMm),
                "--sectors", String(geometry.sectors),
                "--pitch-linear", CLICommandBuilder.number(geometry.pitchLinear),
                "--pitch-quadratic", CLICommandBuilder.number(geometry.pitchQuadratic),
                "--pitch-cubic", CLICommandBuilder.number(geometry.pitchCubic),
                "--invert", CLICommandBuilder.boolean(invertMapping),
                "--dvd-read-compatibility", CLICommandBuilder.boolean(dvdReadCompatibility),
                "--preview-output", preview.path,
                "--burn-output", burn.path,
                "--session-output", session.path,
                "--preview-size", "1600"
            ]
            if let usable = geometry.usableSectors {
                args += ["--usable-sectors", String(usable)]
            }
            isBusy = true
            errorMessage = nil
            status = "Rendering the \(stage.title.lowercased()) target…"
            Task {
                defer { isBusy = false }
                do {
                    let result = try await cliService.run(invocation, arguments: args)
                    let info = try decodeOutput(CalibrationTargetInfo.self, from: result.standardOutput)
                    targetInfo = info
                    targetPreview = DesignRenderer.loadImage(at: info.previewPath, maxPixel: 1600)
                    burnImageURL = URL(fileURLWithPath: info.burnImagePath)
                    sessionURL = URL(fileURLWithPath: info.sessionPath)
                    rectifiedImage = nil
                    tracePoints = []
                    boundarySegments = []
                    solveResult = nil
                    status = "Target ready · \(Int(info.drawingOuterRadiusMm - info.drawingInnerRadiusMm)) mm drawing annulus"
                    preparePhotoRectification()
                } catch {
                    errorMessage = error.localizedDescription
                    status = error.localizedDescription
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            status = error.localizedDescription
        }
    }

    public func generateTargetArtifact(to outputURL: URL) {
        guard !isBusy else { return }
        guard let info = targetInfo, let burnImageURL else {
            errorMessage = "Create a target before generating a burn image."
            return
        }
        do {
            let invocation = try requireCLI()
            let output = outputURL.path
            if output.isEmpty { throw ProjectValidationError.invalidProject("Choose an output file for the target.") }
            let targetGeometry = ProjectGeometry(
                innerRadiusMm: info.innerRadiusMm,
                outerRadiusMm: info.outerRadiusMm,
                sectors: info.sectors,
                pitchLinear: info.pitchLinear,
                pitchQuadratic: info.pitchQuadratic,
                pitchCubic: info.pitchCubic,
                usableSectors: info.usableSectors
            )
            let state = ProjectState(
                name: "Calibration \(stage.title)",
                family: family,
                geometry: targetGeometry,
                layers: [ProjectLayer(name: "calibration-target.png", imagePath: burnImageURL.path)],
                outputs: ProjectOutputs(
                    outputPath: output,
                    writeCue: family == .cd,
                    dataDirectory: "",
                    volumeLabel: "CALIBRATION",
                    interleave: true,
                    filesAtOuterRing: false,
                    dvdReadCompatibility: dvdReadCompatibility
                ),
                tone: .legacyBinary,
                invertMapping: invertMapping
            )
            let args = try CLICommandBuilder.exportArguments(state: state, compositeURL: burnImageURL)
            isBusy = true
            errorMessage = nil
            status = "Generating the calibration artifact…"
            Task {
                defer { isBusy = false }
                do {
                    let result = try await cliService.run(invocation, arguments: args)
                    let artifact = URL(fileURLWithPath: output)
                    if let sessionURL {
                        let sidecar = artifact.deletingPathExtension().appendingPathExtension("calibration.json")
                        try? FileManager.default.removeItem(at: sidecar)
                        try? FileManager.default.copyItem(at: sessionURL, to: sidecar)
                    }
                    generatedArtifactURL = artifact
                    status = "Generated \(artifact.lastPathComponent) · ready to burn"
                    _ = result
                } catch {
                    errorMessage = error.localizedDescription
                    status = error.localizedDescription
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            status = error.localizedDescription
        }
    }

    // MARK: - Photo

    public func importPhoto(at url: URL) {
        guard let image = DesignRenderer.loadImage(at: url.path, maxPixel: 8192) else {
            errorMessage = "Could not read the calibration photo."
            return
        }
        photoURL = url
        photoImage = image
        physicalDiscRadiusMm = geometry.outerRadiusMm <= 45 ? 40 : 60
        preparePhotoRectification()
        resetRectification()
        status = "Mark the physical outer edge and center hole, then calculate rectification."
    }

    public func preparePhotoRectification() {
        guard let image = photoImage else { return }
        let width = Double(image.width)
        let height = Double(image.height)
        let cx = width / 2, cy = height / 2
        let outerRx = width * 0.44, outerRy = height * 0.44
        // The physical hole is 15 mm on a 120 mm disc: 0.125 × the outer radius.
        let holeRx = outerRx * 0.125, holeRy = outerRy * 0.125
        outerPoints = (0..<8).map { index in
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / 8
            return CGPoint(x: cx + outerRx * cos(angle), y: cy + outerRy * sin(angle))
        }
        holePoints = (0..<8).map { index in
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / 8
            return CGPoint(x: cx + holeRx * cos(angle), y: cy + holeRy * sin(angle))
        }
    }

    public func addPhotoPoint(_ point: CGPoint) {
        guard let image = photoImage else { return }
        let x = min(max(point.x, 0), Double(image.width - 1))
        let y = min(max(point.y, 0), Double(image.height - 1))
        let clamped = CGPoint(x: x, y: y)
        switch photoPointMode {
        case .outer:
            if outerPoints.count < 64 { outerPoints.append(clamped) }
        case .hole:
            if holePoints.count < 64 { holePoints.append(clamped) }
        }
        resetRectification()
        status = "\(photoPointMode.title): \(photoPointMode == .outer ? outerPoints.count : holePoints.count) points"
    }

    public func removeLastPhotoPoint() {
        switch photoPointMode {
        case .outer: if !outerPoints.isEmpty { outerPoints.removeLast() }
        case .hole: if !holePoints.isEmpty { holePoints.removeLast() }
        }
        resetRectification()
    }

    public func clearPhotoPoints() {
        if photoPointMode == .outer { outerPoints = [] } else { holePoints = [] }
        resetRectification()
    }

    public func suggestPhotoPoints() {
        preparePhotoRectification()
        resetRectification()
        status = "Suggested 8 outer and 8 hole points. Use Undo/Clear or click to add more."
    }

    public func rectify() {
        guard !isBusy else { return }
        guard let photoURL, photoImage != nil else {
            errorMessage = "Import a photo first."
            return
        }
        guard outerPoints.count >= 5, holePoints.count >= 5 else {
            errorMessage = "Mark at least 5 points on the outer edge and 5 on the center hole."
            return
        }
        do {
            let invocation = try requireCLI()
            let directory = try ensureWorkDirectory()
            let pointsURL = directory.appendingPathComponent("photo-points.json")
            let outputURL = directory.appendingPathComponent("rectified.png")
            let payload = PhotoPointsPayload(
                outer: outerPoints.map { PixelPoint(x: $0.x, y: $0.y) },
                hole: holePoints.map { PixelPoint(x: $0.x, y: $0.y) }
            )
            try ProjectJSON.encoder.encode(payload).write(to: pointsURL, options: .atomic)
            let args = [
                "calibration-rectify",
                "--photo", photoURL.path,
                "--points", pointsURL.path,
                "--physical-outer-radius", CLICommandBuilder.number(physicalDiscRadiusMm),
                "--canvas-radius", CLICommandBuilder.number(physicalDiscRadiusMm + 3),
                "--output", outputURL.path
            ]
            isBusy = true
            errorMessage = nil
            status = "Rectifying the photo…"
            Task {
                defer { isBusy = false }
                do {
                    let result = try await cliService.run(invocation, arguments: args)
                    let decoded = try decodeOutput(CalibrationRectifyResult.self, from: result.standardOutput)
                    guard decoded.succeeded else {
                        errorMessage = decoded.message
                        status = decoded.message
                        return
                    }
                    guard let rectified = DesignRenderer.loadImage(at: outputURL.path, maxPixel: max(480, decoded.pixelSize)) else {
                        throw DesignRenderError.cannotLoadImage(outputURL.path)
                    }
                    rectifiedImage = rectified
                    rectifiedSize = decoded.pixelSize
                    canvasOuterRadiusMm = decoded.canvasOuterRadiusMm
                    rectificationMessage = String(
                        format: "outer RMS %.2f px · hole RMS %.2f px",
                        decoded.outerRmsPixels,
                        decoded.holeRmsPixels
                    )
                    tracePoints = []
                    boundarySegments = []
                    solveResult = nil
                    status = "Rectified · \(rectifiedSize) px · \(rectificationMessage)"
                } catch {
                    errorMessage = error.localizedDescription
                    status = error.localizedDescription
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            status = error.localizedDescription
        }
    }

    public func resetRectification() {
        rectifiedImage = nil
        rectifiedSize = 0
        tracePoints = []
        boundarySegments = []
        solveResult = nil
        rectificationMessage = ""
    }

    // MARK: - Measurements

    public func addMeasurementPoint(_ point: CGPoint) {
        guard let rectifiedImage else { return }
        let x = min(max(point.x, 0), Double(rectifiedImage.width - 1))
        let y = min(max(point.y, 0), Double(rectifiedImage.height - 1))
        let clamped = CGPoint(x: x, y: y)
        if stage == .fine {
            if tracePoints.count < 4000 { tracePoints.append(clamped) }
        } else {
            if boundarySegments.isEmpty { boundarySegments = [[]] }
            activeBoundarySegment = min(activeBoundarySegment, boundarySegments.count - 1)
            if boundarySegments[activeBoundarySegment].count < 4000 {
                boundarySegments[activeBoundarySegment].append(clamped)
            }
        }
        solveResult = nil
    }

    public func removeLastMeasurementPoint() {
        if stage == .fine {
            if !tracePoints.isEmpty { tracePoints.removeLast() }
        } else if boundarySegments.indices.contains(activeBoundarySegment),
                  !boundarySegments[activeBoundarySegment].isEmpty {
            boundarySegments[activeBoundarySegment].removeLast()
        }
        solveResult = nil
    }

    public func newBoundarySegment() {
        guard stage == .boundary else { return }
        boundarySegments.append([])
        activeBoundarySegment = boundarySegments.count - 1
        solveResult = nil
    }

    public func clearMeasurements() {
        tracePoints = []
        boundarySegments = []
        activeBoundarySegment = 0
        solveResult = nil
    }

    public func solve() {
        guard !isBusy else { return }
        guard let sessionURL, rectifiedImage != nil else {
            errorMessage = "Rectify a photo before solving."
            return
        }
        let points = stage == .fine ? tracePoints : boundarySegments.flatMap { $0 }
        guard points.count >= 6 else {
            errorMessage = "Add at least 6 measurement points."
            return
        }
        do {
            let invocation = try requireCLI()
            let directory = try ensureWorkDirectory()
            let pointsURL = directory.appendingPathComponent("measurement-points.json")
            let mmPerPixel = 2 * canvasOuterRadiusMm / Double(max(1, rectifiedSize))
            let centre = Double(rectifiedSize) / 2
            func mm(_ point: CGPoint) -> MMPoint {
                MMPoint(
                    x: (Double(point.x) - centre) * mmPerPixel,
                    y: (Double(point.y) - centre) * mmPerPixel
                )
            }
            let payload: SolvePayload
            if stage == .fine {
                payload = SolvePayload(
                    traces: [TracePayload(armIndex: 0, points: tracePoints.map(mm))],
                    segments: nil,
                    radiusRangeMm: radiusRangeMm,
                    fitPitch: fitPitch,
                    autoRange: autoRange,
                    pitchCoefficientRange: 0.05
                )
            } else {
                payload = SolvePayload(
                    traces: nil,
                    segments: boundarySegments.enumerated().map { index, segment in
                        SegmentPayload(id: index + 1, points: segment.map(mm))
                    },
                    radiusRangeMm: radiusRangeMm,
                    fitPitch: fitPitch,
                    autoRange: autoRange,
                    pitchCoefficientRange: 0.05
                )
            }
            try ProjectJSON.encoder.encode(payload).write(to: pointsURL, options: .atomic)
            let args = [
                "calibration-solve",
                "--session", sessionURL.path,
                "--points", pointsURL.path
            ]
            isBusy = true
            errorMessage = nil
            status = "Fitting the track geometry…"
            Task {
                defer { isBusy = false }
                do {
                    let result = try await cliService.run(invocation, arguments: args)
                    let decoded = try decodeOutput(CalibrationSolveResult.self, from: result.standardOutput)
                    solveResult = decoded
                    if decoded.succeeded, let best = decoded.best {
                        status = String(
                            format: "Fit complete · inner %.4f mm · outer %.4f mm · RMS %.3f mm",
                            best.innerRadiusMm,
                            best.outerRadiusMm,
                            decoded.rmsErrorMm
                        )
                    } else {
                        status = decoded.warnings.first ?? "No valid fit."
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    status = error.localizedDescription
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            status = error.localizedDescription
        }
    }

    public func applyBest(to model: WorkspaceViewModel) {
        guard let best = bestParameters else { return }
        model.apply { state in
            state.geometry.innerRadiusMm = best.innerRadiusMm
            state.geometry.outerRadiusMm = best.outerRadiusMm
            state.geometry.pitchLinear = best.pitchLinear
            state.geometry.pitchQuadratic = best.pitchQuadratic
            state.geometry.pitchCubic = best.pitchCubic
            if state.family == .bd {
                state.invertMapping = best.invertMapping
            }
            if let sessionURL {
                state.calibrationSessionPath = sessionURL.path
            }
        }
        geometry.innerRadiusMm = best.innerRadiusMm
        geometry.outerRadiusMm = best.outerRadiusMm
        geometry.pitchLinear = best.pitchLinear
        geometry.pitchQuadratic = best.pitchQuadratic
        geometry.pitchCubic = best.pitchCubic
        status = "Applied \(String(format: "%.4f", best.innerRadiusMm))–\(String(format: "%.4f", best.outerRadiusMm)) mm. Clear the target to generate the next stage with the updated setup."
    }

    // MARK: - Helpers

    private func resetAll() {
        targetInfo = nil
        targetPreview = nil
        burnImageURL = nil
        sessionURL = nil
        generatedArtifactURL = nil
        photoURL = nil
        photoImage = nil
        outerPoints = []
        holePoints = []
        rectifiedImage = nil
        rectifiedSize = 0
        tracePoints = []
        boundarySegments = []
        activeBoundarySegment = 0
        solveResult = nil
        errorMessage = nil
        rectificationMessage = ""
    }

    private func ensureWorkDirectory() throws -> URL {
        if let workDirectory { return workDirectory }
        let directory = AppPaths.caches.appendingPathComponent("Calibration-\(UUID().uuidString)")
        try AppPaths.ensureDirectory(directory)
        workDirectory = directory
        return directory
    }

    private func requireCLI() throws -> CLIInvocation {
        guard let invocation = cliService.locateCLI(customPath: customCLIPath) else {
            throw CLIError.notFound
        }
        return invocation
    }

    private func decodeOutput<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.firstIndex(of: "{"), let last = trimmed.lastIndex(of: "}") else {
            throw ProjectValidationError.invalidProject("The calibration command returned no JSON.")
        }
        let json = String(trimmed[first...last])
        return try ProjectJSON.decoder.decode(T.self, from: Data(json.utf8))
    }
}
