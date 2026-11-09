import Foundation

/// Builds argument vectors for the cross-platform CLI. Keeping this pure makes the
/// integration testable without launching a process.
public enum CLICommandBuilder {
    public static func exportArguments(state: ProjectState, compositeURL: URL) throws -> [String] {
        try state.geometry.validate(family: state.family)
        let g = state.geometry
        let outputs = state.outputs
        switch state.family {
        case .cd:
            var args = [
                "cd-generate",
                "--input", compositeURL.path,
                "--output", outputs.outputPath,
                "--r0", number(g.innerRadiusMm),
                "--r1", number(g.outerRadiusMm),
                "--sectors", String(g.sectors)
            ]
            if let usable = g.usableSectors {
                args += ["--usable-sectors", String(usable)]
            }
            args += [
                "--pitch-linear", number(g.pitchLinear),
                "--pitch-quadratic", number(g.pitchQuadratic),
                "--pitch-cubic", number(g.pitchCubic),
                "--tone-dither", number(state.tone.ditherStrength),
                "--tone-levels", String(state.tone.levels),
                "--tone-brightness", number(state.tone.brightness),
                "--tone-gamma", boolean(state.tone.srgbLinearization),
                "--interleave", boolean(outputs.interleave),
                "--cue", boolean(outputs.writeCue)
            ]
            if !outputs.dataDirectory.isEmpty {
                args += [
                    "--data-dir", outputs.dataDirectory,
                    "--volume-label", outputs.volumeLabel.isEmpty ? "CD_IMAGE" : outputs.volumeLabel,
                    "--file-position", outputs.filesAtOuterRing ? "outer" : "inner"
                ]
            }
            return args

        case .dvd:
            var args = [
                "solve",
                "--image", compositeURL.path,
                "--iso-output", outputs.outputPath,
                "--total-sectors", String(g.sectors),
                "--inner-radius-mm", number(g.innerRadiusMm),
                "--outer-radius-mm", number(g.outerRadiusMm),
                "--pitch-linear", number(g.pitchLinear),
                "--pitch-quadratic", number(g.pitchQuadratic),
                "--pitch-cubic", number(g.pitchCubic),
                "--tone-dither", number(state.tone.ditherStrength),
                "--tone-levels", String(state.tone.levels),
                "--tone-brightness", number(state.tone.brightness),
                "--tone-gamma", boolean(state.tone.srgbLinearization),
                "--read-compatibility", boolean(outputs.dvdReadCompatibility)
            ]
            if outputs.dataDirectory.isEmpty {
                args += ["--fill-sectors", String(g.usableSectors ?? g.sectors)]
            } else {
                args += [
                    "--data-dir", outputs.dataDirectory,
                    "--volume-label", outputs.volumeLabel.isEmpty ? "DVD_IMAGE" : outputs.volumeLabel,
                    "--file-position", outputs.filesAtOuterRing ? "outer" : "inner"
                ]
            }
            return args

        case .bd:
            var args = [
                "bd-generate",
                "--input", compositeURL.path,
                "--output", outputs.outputPath,
                "--total-sectors", String(g.sectors),
                "--r0", number(g.innerRadiusMm),
                "--r1", number(g.outerRadiusMm),
                "--pitch-linear", number(g.pitchLinear),
                "--pitch-quadratic", number(g.pitchQuadratic),
                "--pitch-cubic", number(g.pitchCubic),
                "--tone-dither", number(state.tone.ditherStrength),
                "--tone-levels", String(min(state.tone.levels, 2)),
                "--tone-brightness", number(state.tone.brightness),
                "--tone-gamma", boolean(state.tone.srgbLinearization),
                "--invert", boolean(state.invertMapping)
            ]
            if let usable = g.usableSectors {
                args += ["--usable-sectors", String(usable)]
            }
            if !outputs.dataDirectory.isEmpty {
                args += [
                    "--data-dir", outputs.dataDirectory,
                    "--volume-label", outputs.volumeLabel.isEmpty ? "BD_IMAGE" : outputs.volumeLabel,
                    "--file-position", outputs.filesAtOuterRing ? "outer" : "inner"
                ]
            }
            return args
        }
    }

    /// Design-projection preview. Returns nil for Blu-ray, which is previewed natively.
    public static func previewArguments(
        state: ProjectState,
        compositeURL: URL,
        outputURL: URL,
        size: Int,
        measuredInnerRadiusMm: Double,
        measuredOuterRadiusMm: Double
    ) throws -> [String]? {
        try state.geometry.validate(family: state.family)
        let g = state.geometry
        let contentOuter = state.contentOuterRadiusMm
        switch state.family {
        case .cd:
            var args = [
                "cd-preview-warp",
                "--input", compositeURL.path,
                "--output", outputURL.path,
                "--r0", number(g.innerRadiusMm),
                "--r1", number(g.outerRadiusMm),
                "--sectors", String(g.sectors),
                "--outer", number(contentOuter),
                "--actual-r0", number(measuredInnerRadiusMm),
                "--actual-r1", number(measuredOuterRadiusMm),
                "--pitch-linear", number(g.pitchLinear),
                "--pitch-quadratic", number(g.pitchQuadratic),
                "--pitch-cubic", number(g.pitchCubic),
                "--actual-pitch-linear", number(g.pitchLinear),
                "--actual-pitch-quadratic", number(g.pitchQuadratic),
                "--actual-pitch-cubic", number(g.pitchCubic),
                "--size", String(size),
                "--samples-per-sector", "16",
                "--tone-dither", number(state.tone.ditherStrength),
                "--tone-levels", String(state.tone.levels),
                "--tone-brightness", number(state.tone.brightness),
                "--tone-gamma", boolean(state.tone.srgbLinearization)
            ]
            if let usable = g.usableSectors {
                args += ["--usable-sectors", String(usable)]
            }
            if !state.outputs.dataDirectory.isEmpty {
                args += [
                    "--data-dir", state.outputs.dataDirectory,
                    "--volume-label", state.outputs.volumeLabel.isEmpty ? "CD_IMAGE" : state.outputs.volumeLabel,
                    "--file-position", state.outputs.filesAtOuterRing ? "outer" : "inner"
                ]
            }
            return args

        case .dvd:
            return [
                "calibrate",
                "--image", compositeURL.path,
                "--output", outputURL.path,
                "--total-sectors", String(g.sectors),
                "--inner-radius-mm", number(g.innerRadiusMm),
                "--outer-radius-mm", number(g.outerRadiusMm),
                "--actual-inner-radius-mm", number(measuredInnerRadiusMm),
                "--actual-outer-radius-mm", number(measuredOuterRadiusMm),
                "--pitch-linear", number(g.pitchLinear),
                "--pitch-quadratic", number(g.pitchQuadratic),
                "--pitch-cubic", number(g.pitchCubic),
                "--actual-pitch-linear", number(g.pitchLinear),
                "--actual-pitch-quadratic", number(g.pitchQuadratic),
                "--actual-pitch-cubic", number(g.pitchCubic),
                "--preview-size", String(size),
                "--samples-per-sector", "16",
                "--tone-dither", number(state.tone.ditherStrength),
                "--tone-levels", String(min(state.tone.levels, 2)),
                "--tone-brightness", number(state.tone.brightness),
                "--tone-gamma", boolean(state.tone.srgbLinearization)
            ]

        case .bd:
            return nil
        }
    }

    /// Read-back preview of an already generated artifact. Returns nil when the target
    /// artifact does not exist or the family has no standalone read-back command.
    public static func readbackArguments(
        state: ProjectState,
        outputURL: URL,
        size: Int
    ) -> [String]? {
        guard FileManager.default.fileExists(atPath: state.outputs.outputPath) else { return nil }
        let g = state.geometry
        switch state.family {
        case .cd:
            var args = [
                "cd-preview-track",
                "--track", state.outputs.outputPath,
                "--output", outputURL.path,
                "--r0", number(g.innerRadiusMm),
                "--r1", number(g.outerRadiusMm),
                "--sectors", String(g.sectors),
                "--size", String(size),
                "--byte-step", "48",
                "--deinterleave", "true"
            ]
            if let usable = g.usableSectors {
                args += ["--usable-sectors", String(usable)]
            }
            return args
        case .dvd:
            return [
                "simulate",
                "--iso", state.outputs.outputPath,
                "--output", outputURL.path,
                "--total-sectors", String(g.sectors),
                "--inner-radius-mm", number(g.innerRadiusMm),
                "--outer-radius-mm", number(g.outerRadiusMm),
                "--preview-size", String(size),
                "--samples-per-sector", "16"
            ]
        case .bd:
            return nil
        }
    }

    public static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1e12 {
            return String(Int64(value))
        }
        return String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    public static func boolean(_ value: Bool) -> String { value ? "true" : "false" }
}
