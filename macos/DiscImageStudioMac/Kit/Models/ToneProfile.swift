import Foundation

/// Native mirror of `DiscImageStudio.Core.ToneProfile`. The deterministic dither phase is
/// keyed to the same logical sample index so previews look like the engine's output.
public struct ToneProfile: Codable, Equatable, Sendable {
    public var ditherStrength: Double
    public var levels: Int
    public var brightness: Double
    public var srgbLinearization: Bool

    public static let twoLevels = 2
    public static let fourLevels = 4
    public static let legacyBinary = ToneProfile(
        ditherStrength: 0,
        levels: twoLevels,
        brightness: 0,
        srgbLinearization: false
    )
    public static let photo = ToneProfile(
        ditherStrength: 0.75,
        levels: twoLevels,
        brightness: 0,
        srgbLinearization: false
    )

    public init(
        ditherStrength: Double,
        levels: Int = twoLevels,
        brightness: Double = 0,
        srgbLinearization: Bool = false
    ) {
        self.ditherStrength = ditherStrength
        self.levels = levels
        self.brightness = brightness
        self.srgbLinearization = srgbLinearization
    }

    private enum CodingKeys: String, CodingKey {
        case ditherStrength, levels, brightness, srgbLinearization
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ditherStrength = try c.decodeIfPresent(Double.self, forKey: .ditherStrength) ?? 0
        levels = try c.decodeIfPresent(Int.self, forKey: .levels) ?? ToneProfile.twoLevels
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        srgbLinearization = try c.decodeIfPresent(Bool.self, forKey: .srgbLinearization) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ditherStrength, forKey: .ditherStrength)
        try c.encode(levels, forKey: .levels)
        try c.encode(brightness, forKey: .brightness)
        try c.encode(srgbLinearization, forKey: .srgbLinearization)
    }

    public var isLegacyBinary: Bool {
        ditherStrength <= 0 && levels == ToneProfile.twoLevels
            && brightness == 0 && !srgbLinearization
    }

    public var isDvdCompatible: Bool { levels == ToneProfile.twoLevels }

    public func validate() throws {
        guard ditherStrength.isFinite, (0...1).contains(ditherStrength) else {
            throw ProjectValidationError.invalidProject("Dither strength must be between 0 and 1.")
        }
        guard levels == ToneProfile.twoLevels || levels == ToneProfile.fourLevels else {
            throw ProjectValidationError.invalidProject("Tone levels must be 2 or 4.")
        }
        guard brightness.isFinite, (-64...64).contains(brightness) else {
            throw ProjectValidationError.invalidProject("Tone brightness must be between -64 and 64.")
        }
    }

    public func normalized() -> ToneProfile {
        ToneProfile(
            ditherStrength: min(max(ditherStrength.isFinite ? ditherStrength : 0, 0), 1),
            levels: levels == ToneProfile.fourLevels ? ToneProfile.fourLevels : ToneProfile.twoLevels,
            brightness: min(max(brightness.isFinite ? brightness : 0, -64), 64),
            srgbLinearization: srgbLinearization
        )
    }

    private static let linearValues: [Double] = (0...255).map { gray in
        let value = Double(gray) / 255.0
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    /// Exact native port of `ToneProfile.AdjustedGray`.
    public func adjustedGray(_ gray: UInt8) -> UInt8 {
        var value = srgbLinearization ? ToneProfile.linearValues[Int(gray)] : Double(gray) / 255.0
        value = min(max(value + brightness / 255.0, 0), 1)
        return UInt8((value * 255.0).rounded())
    }

    public func useWhite(gray: UInt8, sampleIndex: Int64, threshold: UInt8 = 128) -> Bool {
        if isLegacyBinary {
            return gray >= threshold
        }
        let strength = min(max(ditherStrength, 0), 1)
        let shiftedThreshold = Double(threshold) + strength * 255.0 * (ToneProfile.phase(sampleIndex) - 0.5)
        return Double(adjustedGray(gray)) >= shiftedThreshold
    }

    /// Nominal preview luminance for one source pixel. Two-level output matches the
    /// engine's threshold; four-level output uses the same nominal palette as the CD
    /// four-level mode.
    public func quantizedGray(gray: UInt8, sampleIndex: Int64) -> UInt8 {
        if levels == ToneProfile.fourLevels {
            let strength = min(max(ditherStrength, 0), 1)
            let shifted = Double(adjustedGray(gray)) + (ToneProfile.phase(sampleIndex) - 0.5) * strength * 85.0
            let index = min(max(Int((shifted / 85.0).rounded()), 0), 3)
            return UInt8(index * 85)
        }
        return useWhite(gray: gray, sampleIndex: sampleIndex) ? 255 : 0
    }

    /// Same 32-bit hash as `ToneDither.Phase`.
    public static func phase(_ sampleIndex: Int64) -> Double {
        var value = UInt32(truncatingIfNeeded: sampleIndex) &* 2_654_435_761
        value ^= value >> 16
        value = value &* 0x7FEB_352D
        value ^= value >> 15
        value = value &* 0x846C_A68B
        value ^= value >> 16
        return Double(value) / 4_294_967_296.0
    }

    public var summary: String {
        let dither = Int((ditherStrength * 100).rounded())
        return "\(levels) levels · \(dither)% dither · \(Int(brightness)) brightness"
            + (srgbLinearization ? " · sRGB linear" : "")
    }
}
