import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Developer-only preflight switches used by the verification scripts. They run before
/// SwiftUI starts and exit immediately, so they never affect normal app usage.
public enum DebugSupport {
    public static func runPreflightIfRequested() {
        let arguments = CommandLine.arguments
        if arguments.contains("--probe-engine") {
            probeEngine()
            return
        }
        guard let index = arguments.firstIndex(of: "--write-sample-project"),
              index + 1 < arguments.count
        else { return }

        let url = URL(fileURLWithPath: (arguments[index + 1] as NSString).expandingTildeInPath)
        let document = ProjectDocument(
            name: "SwiftUI Compatibility Fixture",
            discFamily: ProjectDocument.familyCode(for: .dvd),
            geometry: ProjectGeometry(
                innerRadiusMm: 23.991460627731737,
                outerRadiusMm: 57.964893657925366,
                sectors: 2_297_888,
                pitchLinear: -3.9256854319227684e-05,
                pitchQuadratic: 6.964795915429256e-05,
                pitchCubic: -4.670918950137523e-05,
                usableSectors: 2_297_888
            ),
            layers: [
                ProjectLayer(
                    id: "fixture-layer",
                    name: "fixture.png",
                    imagePath: "/tmp/fixture.png",
                    visible: true,
                    translateXMm: 3.25,
                    translateYMm: -2.5,
                    rotationDeg: 17.5,
                    scale: 0.85
                )
            ],
            outputs: ProjectOutputs(
                outputPath: url.deletingPathExtension().appendingPathExtension("iso").path,
                writeCue: true,
                dataDirectory: "",
                volumeLabel: "SWIFT_FIXTURE",
                interleave: true,
                filesAtOuterRing: false,
                dvdReadCompatibility: true
            ),
            calibrationSessionPath: nil,
            thumbnailPngBase64: nil,
            createdUtc: Date(timeIntervalSince1970: 1_761_000_000),
            modifiedUtc: Date(timeIntervalSince1970: 1_761_000_100),
            tone: ToneProfile(ditherStrength: 0.75, levels: 2, brightness: 3, srgbLinearization: true),
            bluRay: nil
        )
        do {
            try ProjectStore.save(document, to: url)
            print("wrote SwiftUI project fixture: \(url.path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("fixture error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func probeEngine() {
        guard let invocation = CLIService.shared.locateCLI() else {
            print("engine: not found")
            exit(1)
        }
        print("engine: \(invocation.executableURL.path) \(invocation.prefixArguments.joined(separator: " ")) (\(invocation.source))")
        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.prefixArguments + ["--help"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)
            print(text.split(separator: "\n").prefix(2).joined(separator: "\n"))
            exit(process.terminationStatus == 0 ? 0 : 1)
        } catch {
            print("engine launch failed: \(error.localizedDescription)")
            exit(1)
        }
    }
}
