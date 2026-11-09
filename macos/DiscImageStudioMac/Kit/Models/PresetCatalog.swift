import Foundation

/// A selectable disc geometry preset. Built-ins come from the engine's own
/// `built-in-disc-presets.json` so the two frontends cannot drift apart.
public struct DiscPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let family: DiscFamily
    public let geometry: ProjectGeometry
    public let invertMapping: Bool
    public let contributor: String?

    public init(
        id: String,
        name: String,
        detail: String,
        family: DiscFamily,
        geometry: ProjectGeometry,
        invertMapping: Bool = false,
        contributor: String? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.family = family
        self.geometry = geometry
        self.invertMapping = invertMapping
        self.contributor = contributor
    }
}

public enum PresetCatalog {
    public static let all: [DiscPreset] = load()

    public static func presets(for family: DiscFamily) -> [DiscPreset] {
        all.filter { $0.family == family }
    }

    public static func preset(id: String) -> DiscPreset? {
        all.first { $0.id == id }
    }

    /// The closest built-in preset for a geometry, used to pre-select the picker.
    public static func matching(_ geometry: ProjectGeometry, family: DiscFamily) -> DiscPreset? {
        presets(for: family).first { preset in
            abs(preset.geometry.innerRadiusMm - geometry.innerRadiusMm) < 0.000_001
                && abs(preset.geometry.outerRadiusMm - geometry.outerRadiusMm) < 0.000_001
                && preset.geometry.sectors == geometry.sectors
        }
    }

    // MARK: - Resource decoding

    private struct PresetDocument: Decodable {
        let cdPresets: [PresetDefinition]?
        let dvdPresets: [PresetDefinition]?
        let bluRayPresets: [PresetDefinition]?
    }

    private struct PresetDefinition: Decodable {
        let id: String
        let displayName: String?
        let description: String?
        let sectors: Int64?
        let totalSectors: Int64?
        let usableSectors: Int64?
        let innerRadiusMm: Double
        let outerRadiusMm: Double
        let pitchLinear: Double?
        let pitchQuadratic: Double?
        let pitchCubic: Double?
        let invertMapping: Bool?
        let contributor: String?
    }

    private final class BundleToken {}

    private static func load() -> [DiscPreset] {
        var result: [DiscPreset] = []
        let bundle = Bundle(for: BundleToken.self)
        if let url = bundle.url(forResource: "built-in-disc-presets", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let document = try? JSONDecoder().decode(PresetDocument.self, from: data) {
            result.append(contentsOf: convert(document.cdPresets ?? [], family: .cd))
            result.append(contentsOf: convert(document.dvdPresets ?? [], family: .dvd))
            result.append(contentsOf: convert(document.bluRayPresets ?? [], family: .bd))
        }
        if result.isEmpty {
            result = fallbackPresets
        }
        return result
    }

    private static func convert(_ definitions: [PresetDefinition], family: DiscFamily) -> [DiscPreset] {
        definitions.map { definition in
            let sectors = definition.sectors ?? definition.totalSectors ?? family.defaultGeometry.sectors
            let geometry = ProjectGeometry(
                innerRadiusMm: definition.innerRadiusMm,
                outerRadiusMm: definition.outerRadiusMm,
                sectors: sectors,
                pitchLinear: definition.pitchLinear ?? 0,
                pitchQuadratic: definition.pitchQuadratic ?? 0,
                pitchCubic: definition.pitchCubic ?? 0,
                usableSectors: definition.usableSectors
            )
            return DiscPreset(
                id: definition.id,
                name: englishName(for: definition.id, fallback: definition.displayName ?? definition.id),
                detail: detailText(for: definition, geometry: geometry, family: family),
                family: family,
                geometry: geometry,
                invertMapping: definition.invertMapping ?? false,
                contributor: definition.contributor
            )
        }
    }

    private static func detailText(
        for definition: PresetDefinition,
        geometry: ProjectGeometry,
        family: DiscFamily
    ) -> String {
        let radii = String(format: "%.3f–%.3f mm", geometry.innerRadiusMm, geometry.outerRadiusMm)
        let sectors = geometry.sectors.formatted(.number.grouping(.automatic))
        let calibrated = geometry.pitchLinear != 0 || geometry.pitchQuadratic != 0 || geometry.pitchCubic != 0
        let source = calibrated ? "Measured cubic-pitch calibration" : "Nominal \(family.label) geometry"
        let contributor = definition.contributor.map { " · \($0)" } ?? ""
        return "\(source) · \(radii) · \(sectors) sectors\(contributor)"
    }

    static func englishName(for id: String, fallback: String) -> String {
        let names: [String: String] = [
            "cd-80": "Standard 80-minute CD",
            "cd-74": "Standard 74-minute CD",
            "ritek-medical-aqua": "Ritek Medical Aqua CD (measured)",
            "verbatim-azo-43438": "Verbatim CD-R AZO 43438 (measured)",
            "dvd-5-120mm": "Standard 12 cm DVD-5",
            "dvd-5-80mm": "Standard 8 cm DVD",
            "verbatim-dvd-r-azo-43533": "Verbatim DVD-R AZO 43533 (measured)",
            "verbatim-dvd-r-azo-43523": "Verbatim DVD-R AZO 43523 (measured)",
            "verbatim-dvd-plus-r-azo-43498": "Verbatim DVD+R AZO 43498 (measured)",
            "philips-dvd-plus-r": "Philips DVD+R (measured)",
            "ritek-dvd-plus-r-e-series": "Ritek DVD+R E-series (measured)",
            "ritek-dvd-r-e-series": "Ritek DVD-R E-series (measured)",
            "bd-r-sl-25gb": "Standard BD-R 25 GB",
            "bd-r-ritek-10x": "Ritek BD-R 10× (measured)",
            "bd-r-ritek-12x": "Ritek BD-R 12× (measured)",
            "bd-r-verbatim-64099": "Verbatim BD-R 64099 (measured)",
            "bd-r-verbatim-64293": "Verbatim BD-R 64293 (measured)"
        ]
        return names[id] ?? fallback
    }

    private static let fallbackPresets: [DiscPreset] = [
        DiscPreset(
            id: "cd-80",
            name: "Standard 80-minute CD",
            detail: "Nominal CD geometry · 24.500–56.800 mm · 359,849 sectors",
            family: .cd,
            geometry: DiscFamily.cd.defaultGeometry
        ),
        DiscPreset(
            id: "dvd-5-120mm",
            name: "Standard 12 cm DVD-5",
            detail: "Nominal DVD geometry · 24.000–58.000 mm · 2,295,104 sectors",
            family: .dvd,
            geometry: DiscFamily.dvd.defaultGeometry
        ),
        DiscPreset(
            id: "bd-r-sl-25gb",
            name: "Standard BD-R 25 GB",
            detail: "Nominal BD-R geometry · 24.000–58.000 mm · 12,219,392 sectors",
            family: .bd,
            geometry: DiscFamily.bd.defaultGeometry
        )
    ]
}
