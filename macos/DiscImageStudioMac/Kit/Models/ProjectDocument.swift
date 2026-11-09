import Foundation

/// The three optical-disc families supported by the engine.
public enum DiscFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case cd
    case dvd
    case bd

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cd: return "CD"
        case .dvd: return "DVD"
        case .bd: return "Blu-ray"
        }
    }

    public var shortLabel: String {
        switch self {
        case .cd: return "CD"
        case .dvd: return "DVD"
        case .bd: return "BD"
        }
    }

    public var tagline: String {
        switch self {
        case .cd: return "Audio or Mode 1 data"
        case .dvd: return "DVD-Video style ISO"
        case .bd: return "Single-layer BD-R 25 GB"
        }
    }

    public var systemImage: String {
        switch self {
        case .cd: return "opticaldisc"
        case .dvd: return "opticaldisc.fill"
        case .bd: return "opticaldiscdrive"
        }
    }

    public var defaultOutputExtension: String {
        self == .cd ? "wav" : "iso"
    }

    public var sectorAlignment: Int64 {
        switch self {
        case .cd: return 1
        case .dvd: return 16
        case .bd: return 32
        }
    }

    public var userPresetsSubdirectory: String { rawValue }

    public var defaultGeometry: ProjectGeometry {
        switch self {
        case .cd:
            return ProjectGeometry(
                innerRadiusMm: 24.5,
                outerRadiusMm: 56.8,
                sectors: 359_849,
                usableSectors: 359_847
            )
        case .dvd:
            return ProjectGeometry(
                innerRadiusMm: 24.0,
                outerRadiusMm: 58.0,
                sectors: 2_295_104,
                usableSectors: 2_295_104
            )
        case .bd:
            return ProjectGeometry(
                innerRadiusMm: 24.0,
                outerRadiusMm: 58.0,
                sectors: 12_219_392,
                usableSectors: 12_219_392
            )
        }
    }
}

// MARK: - Geometry

public struct ProjectGeometry: Codable, Equatable, Sendable {
    public var innerRadiusMm: Double
    public var outerRadiusMm: Double
    public var sectors: Int64
    public var pitchLinear: Double
    public var pitchQuadratic: Double
    public var pitchCubic: Double
    public var usableSectors: Int64?

    public init(
        innerRadiusMm: Double,
        outerRadiusMm: Double,
        sectors: Int64,
        pitchLinear: Double = 0,
        pitchQuadratic: Double = 0,
        pitchCubic: Double = 0,
        usableSectors: Int64? = nil
    ) {
        self.innerRadiusMm = innerRadiusMm
        self.outerRadiusMm = outerRadiusMm
        self.sectors = sectors
        self.pitchLinear = pitchLinear
        self.pitchQuadratic = pitchQuadratic
        self.pitchCubic = pitchCubic
        self.usableSectors = usableSectors
    }

    private enum CodingKeys: String, CodingKey {
        case innerRadiusMm, outerRadiusMm, sectors
        case pitchLinear, pitchQuadratic, pitchCubic, usableSectors
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        innerRadiusMm = try c.decode(Double.self, forKey: .innerRadiusMm)
        outerRadiusMm = try c.decode(Double.self, forKey: .outerRadiusMm)
        sectors = try c.decode(Int64.self, forKey: .sectors)
        pitchLinear = try c.decodeIfPresent(Double.self, forKey: .pitchLinear) ?? 0
        pitchQuadratic = try c.decodeIfPresent(Double.self, forKey: .pitchQuadratic) ?? 0
        pitchCubic = try c.decodeIfPresent(Double.self, forKey: .pitchCubic) ?? 0
        usableSectors = try c.decodeIfPresent(Int64.self, forKey: .usableSectors)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(innerRadiusMm, forKey: .innerRadiusMm)
        try c.encode(outerRadiusMm, forKey: .outerRadiusMm)
        try c.encode(sectors, forKey: .sectors)
        try c.encode(pitchLinear, forKey: .pitchLinear)
        try c.encode(pitchQuadratic, forKey: .pitchQuadratic)
        try c.encode(pitchCubic, forKey: .pitchCubic)
        try c.encodeIfPresent(usableSectors, forKey: .usableSectors)
    }

    /// Radius of the last writable sector. The engine uses this as the edge of the
    /// source picture, so the native canvas uses exactly the same value.
    public func contentOuterRadiusMm(family: DiscFamily) -> Double {
        guard let usableSectors, usableSectors > 0, usableSectors < sectors else {
            return outerRadiusMm
        }
        // Constant-pitch rings follow r² linearly in track length. Variable-pitch
        // geometry is calibrated in the engine; using the nominal outer radius keeps
        // the canvas conservative for those presets.
        if pitchLinear != 0 || pitchQuadratic != 0 || pitchCubic != 0 {
            return outerRadiusMm
        }
        let ratio = Double(usableSectors) / Double(sectors)
        let innerSquared = innerRadiusMm * innerRadiusMm
        let outerSquared = outerRadiusMm * outerRadiusMm
        return sqrt(innerSquared + ratio * (outerSquared - innerSquared))
    }

    public func validate(family: DiscFamily) throws {
        guard innerRadiusMm.isFinite, innerRadiusMm > 0 else {
            throw ProjectValidationError.invalidGeometry("Inner radius must be a positive number.")
        }
        guard outerRadiusMm.isFinite, outerRadiusMm > innerRadiusMm else {
            throw ProjectValidationError.invalidGeometry("Outer radius must be greater than the inner radius.")
        }
        guard sectors > 0 else {
            throw ProjectValidationError.invalidGeometry("Sector count must be greater than zero.")
        }
        if family == .bd {
            guard sectors <= 12_219_392 else {
                throw ProjectValidationError.invalidGeometry("A single-layer BD-R holds at most 12,219,392 sectors.")
            }
            guard sectors % 32 == 0 else {
                throw ProjectValidationError.invalidGeometry("Blu-ray sector count must be a multiple of 32.")
            }
            guard outerRadiusMm <= 60 else {
                throw ProjectValidationError.invalidGeometry("Blu-ray outer radius cannot exceed 60 mm.")
            }
        }
        if let usableSectors {
            guard usableSectors > 0, usableSectors <= sectors else {
                throw ProjectValidationError.invalidGeometry("Usable sectors must be greater than zero and no larger than the total.")
            }
            guard usableSectors % family.sectorAlignment == 0 else {
                throw ProjectValidationError.invalidGeometry(
                    "Usable sectors must be a multiple of \(family.sectorAlignment) for \(family.label)."
                )
            }
        }
        for value in [pitchLinear, pitchQuadratic, pitchCubic] where !value.isFinite {
            throw ProjectValidationError.invalidGeometry("Pitch coefficients must be finite numbers.")
        }
    }
}

// MARK: - Layers

public struct ProjectLayer: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var imagePath: String
    public var visible: Bool
    public var translateXMm: Double
    public var translateYMm: Double
    public var rotationDeg: Double
    public var scale: Double

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        imagePath: String,
        visible: Bool = true,
        translateXMm: Double = 0,
        translateYMm: Double = 0,
        rotationDeg: Double = 0,
        scale: Double = 1
    ) {
        self.id = id
        self.name = name
        self.imagePath = imagePath
        self.visible = visible
        self.translateXMm = translateXMm
        self.translateYMm = translateYMm
        self.rotationDeg = rotationDeg
        self.scale = scale
    }

    public var imageURL: URL { URL(fileURLWithPath: imagePath) }
}

// MARK: - Outputs

public struct ProjectOutputs: Codable, Equatable, Sendable {
    public var outputPath: String
    public var writeCue: Bool
    public var dataDirectory: String
    public var volumeLabel: String
    public var interleave: Bool
    public var filesAtOuterRing: Bool
    public var dvdReadCompatibility: Bool

    public init(
        outputPath: String,
        writeCue: Bool = true,
        dataDirectory: String = "",
        volumeLabel: String = "DISC_IMAGE",
        interleave: Bool = true,
        filesAtOuterRing: Bool = false,
        dvdReadCompatibility: Bool = false
    ) {
        self.outputPath = outputPath
        self.writeCue = writeCue
        self.dataDirectory = dataDirectory
        self.volumeLabel = volumeLabel
        self.interleave = interleave
        self.filesAtOuterRing = filesAtOuterRing
        self.dvdReadCompatibility = dvdReadCompatibility
    }

    private enum CodingKeys: String, CodingKey {
        case outputPath, writeCue, dataDirectory, volumeLabel, interleave
        case filesAtOuterRing, dvdReadCompatibility
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        outputPath = try c.decode(String.self, forKey: .outputPath)
        writeCue = try c.decodeIfPresent(Bool.self, forKey: .writeCue) ?? true
        dataDirectory = try c.decodeIfPresent(String.self, forKey: .dataDirectory) ?? ""
        volumeLabel = try c.decodeIfPresent(String.self, forKey: .volumeLabel) ?? "DISC_IMAGE"
        interleave = try c.decodeIfPresent(Bool.self, forKey: .interleave) ?? true
        filesAtOuterRing = try c.decodeIfPresent(Bool.self, forKey: .filesAtOuterRing) ?? false
        dvdReadCompatibility = try c.decodeIfPresent(Bool.self, forKey: .dvdReadCompatibility) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(outputPath, forKey: .outputPath)
        try c.encode(writeCue, forKey: .writeCue)
        try c.encode(dataDirectory, forKey: .dataDirectory)
        try c.encode(volumeLabel, forKey: .volumeLabel)
        try c.encode(interleave, forKey: .interleave)
        try c.encode(filesAtOuterRing, forKey: .filesAtOuterRing)
        try c.encode(dvdReadCompatibility, forKey: .dvdReadCompatibility)
    }
}

// MARK: - Blu-ray settings

public struct ProjectBluRaySettings: Codable, Equatable, Sendable {
    public var invertMapping: Bool

    public init(invertMapping: Bool = false) {
        self.invertMapping = invertMapping
    }
}

// MARK: - Project document (on-disk schema 2)

/// Mirrors `DiscImageStudio.Core.ProjectJsonStore.ProjectDocument` exactly.
public struct ProjectDocument: Codable, Equatable, Sendable {
    public static let cdFamily = "cd"
    public static let dvdFamily = "dvd"
    public static let bluRayFamily = "bd"
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var name: String
    public var discFamily: String
    public var geometry: ProjectGeometry
    public var layers: [ProjectLayer]
    public var outputs: ProjectOutputs
    public var calibrationSessionPath: String?
    public var thumbnailPngBase64: String?
    public var createdUtc: Date
    public var modifiedUtc: Date
    public var tone: ToneProfile?
    public var bluRay: ProjectBluRaySettings?

    public init(
        schemaVersion: Int = ProjectDocument.currentSchemaVersion,
        name: String,
        discFamily: String,
        geometry: ProjectGeometry,
        layers: [ProjectLayer],
        outputs: ProjectOutputs,
        calibrationSessionPath: String? = nil,
        thumbnailPngBase64: String? = nil,
        createdUtc: Date = Date(),
        modifiedUtc: Date = Date(),
        tone: ToneProfile? = nil,
        bluRay: ProjectBluRaySettings? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.discFamily = discFamily
        self.geometry = geometry
        self.layers = layers
        self.outputs = outputs
        self.calibrationSessionPath = calibrationSessionPath
        self.thumbnailPngBase64 = thumbnailPngBase64
        self.createdUtc = createdUtc
        self.modifiedUtc = modifiedUtc
        self.tone = tone
        self.bluRay = bluRay
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, name, discFamily, geometry, layers, outputs
        case calibrationSessionPath, thumbnailPngBase64, createdUtc, modifiedUtc
        case tone, bluRay
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        name = try c.decode(String.self, forKey: .name)
        discFamily = try c.decode(String.self, forKey: .discFamily)
        geometry = try c.decode(ProjectGeometry.self, forKey: .geometry)
        layers = try c.decode([ProjectLayer].self, forKey: .layers)
        outputs = try c.decode(ProjectOutputs.self, forKey: .outputs)
        calibrationSessionPath = try c.decodeIfPresent(String.self, forKey: .calibrationSessionPath)
        thumbnailPngBase64 = try c.decodeIfPresent(String.self, forKey: .thumbnailPngBase64)
        createdUtc = try c.decode(Date.self, forKey: .createdUtc)
        modifiedUtc = try c.decode(Date.self, forKey: .modifiedUtc)
        tone = try c.decodeIfPresent(ToneProfile.self, forKey: .tone)
        bluRay = try c.decodeIfPresent(ProjectBluRaySettings.self, forKey: .bluRay)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ProjectDocument.currentSchemaVersion, forKey: .schemaVersion)
        try c.encode(name, forKey: .name)
        try c.encode(discFamily, forKey: .discFamily)
        try c.encode(geometry, forKey: .geometry)
        try c.encode(layers, forKey: .layers)
        try c.encode(outputs, forKey: .outputs)
        try c.encodeIfPresent(calibrationSessionPath, forKey: .calibrationSessionPath)
        try c.encodeIfPresent(thumbnailPngBase64, forKey: .thumbnailPngBase64)
        try c.encode(createdUtc, forKey: .createdUtc)
        try c.encode(modifiedUtc, forKey: .modifiedUtc)
        try c.encodeIfPresent(tone, forKey: .tone)
        try c.encodeIfPresent(bluRay, forKey: .bluRay)
    }

    public var family: DiscFamily {
        switch discFamily.lowercased() {
        case DiscFamily.dvd.rawValue: return .dvd
        case DiscFamily.bd.rawValue: return .bd
        default: return .cd
        }
    }

    public static func familyCode(for family: DiscFamily) -> String {
        switch family {
        case .cd: return cdFamily
        case .dvd: return dvdFamily
        case .bd: return bluRayFamily
        }
    }

    public func validate() throws {
        guard schemaVersion == 1 || schemaVersion == 2 else {
            throw ProjectValidationError.unsupportedSchema(schemaVersion)
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectValidationError.invalidProject("Project name cannot be empty.")
        }
        guard [ProjectDocument.cdFamily, ProjectDocument.dvdFamily, ProjectDocument.bluRayFamily]
            .contains(discFamily.lowercased())
        else {
            throw ProjectValidationError.invalidProject("Unknown disc family '\(discFamily)'.")
        }
        try geometry.validate(family: family)
        if schemaVersion == 1 && (family == .bd || bluRay != nil) {
            throw ProjectValidationError.invalidProject("Schema 1 projects cannot contain Blu-ray settings.")
        }
        if family != .bd && bluRay != nil {
            throw ProjectValidationError.invalidProject("Blu-ray settings are only valid for Blu-ray projects.")
        }
        var ids = Set<String>()
        for layer in layers {
            guard !layer.id.isEmpty, ids.insert(layer.id).inserted else {
                throw ProjectValidationError.invalidProject("Layer ids must be unique and non-empty.")
            }
            guard !layer.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProjectValidationError.invalidProject("Layer '\(layer.id)' has an empty name.")
            }
            guard !layer.imagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProjectValidationError.invalidProject("Layer '\(layer.name)' has no image path.")
            }
            guard layer.scale.isFinite, layer.scale > 0 else {
                throw ProjectValidationError.invalidProject("Layer '\(layer.name)' scale must be greater than zero.")
            }
            guard layer.translateXMm.isFinite, layer.translateYMm.isFinite,
                  layer.rotationDeg.isFinite
            else {
                throw ProjectValidationError.invalidProject("Layer '\(layer.name)' transform contains a non-finite value.")
            }
        }
        guard !outputs.outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectValidationError.invalidProject("Choose an output path for the project.")
        }
        if let tone {
            try tone.validate()
        }
    }
}

// MARK: - Editable project state

/// The model behind the editor. It is intentionally separate from the file record so
/// transient UI concerns (selection, previews, logs) never leak into `.discproj`.
public struct ProjectState: Equatable, Sendable {
    public var name: String
    public var family: DiscFamily
    public var geometry: ProjectGeometry
    public var layers: [ProjectLayer]
    public var outputs: ProjectOutputs
    public var tone: ToneProfile
    public var invertMapping: Bool
    public var calibrationSessionPath: String?
    public var createdUtc: Date
    public var modifiedUtc: Date
    public var thumbnailPngBase64: String?

    public init(document: ProjectDocument) {
        name = document.name
        family = document.family
        geometry = document.geometry
        layers = document.layers
        outputs = document.outputs
        tone = document.tone ?? .legacyBinary
        invertMapping = document.bluRay?.invertMapping ?? false
        calibrationSessionPath = document.calibrationSessionPath
        createdUtc = document.createdUtc
        modifiedUtc = document.modifiedUtc
        thumbnailPngBase64 = document.thumbnailPngBase64
    }

    public init(
        name: String,
        family: DiscFamily,
        geometry: ProjectGeometry,
        layers: [ProjectLayer] = [],
        outputs: ProjectOutputs,
        tone: ToneProfile = .photo,
        invertMapping: Bool = false,
        calibrationSessionPath: String? = nil,
        createdUtc: Date = Date(),
        modifiedUtc: Date = Date(),
        thumbnailPngBase64: String? = nil
    ) {
        self.name = name
        self.family = family
        self.geometry = geometry
        self.layers = layers
        self.outputs = outputs
        self.tone = tone
        self.invertMapping = invertMapping
        self.calibrationSessionPath = calibrationSessionPath
        self.createdUtc = createdUtc
        self.modifiedUtc = modifiedUtc
        self.thumbnailPngBase64 = thumbnailPngBase64
    }

    public var contentOuterRadiusMm: Double {
        geometry.contentOuterRadiusMm(family: family)
    }

    public func document() -> ProjectDocument {
        ProjectDocument(
            name: name,
            discFamily: ProjectDocument.familyCode(for: family),
            geometry: geometry,
            layers: layers,
            outputs: outputs,
            calibrationSessionPath: calibrationSessionPath,
            thumbnailPngBase64: thumbnailPngBase64,
            createdUtc: createdUtc,
            modifiedUtc: modifiedUtc,
            tone: tone,
            bluRay: family == .bd ? ProjectBluRaySettings(invertMapping: invertMapping) : nil
        )
    }
}

// MARK: - Errors

public enum ProjectValidationError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case invalidProject(String)
    case invalidGeometry(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "Unsupported project schema \(version). This app reads schema 1 and 2."
        case .invalidProject(let message):
            return message
        case .invalidGeometry(let message):
            return message
        }
    }
}
