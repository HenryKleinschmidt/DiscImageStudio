import CoreGraphics
import XCTest
@testable import DiscImageStudioKit

final class ProjectDocumentTests: XCTestCase {
    private func sampleDocument(family: DiscFamily = .dvd) -> ProjectDocument {
        let geometry = family.defaultGeometry
        return ProjectDocument(
            name: "Compatibility Test",
            discFamily: ProjectDocument.familyCode(for: family),
            geometry: geometry,
            layers: [
                ProjectLayer(
                    id: "layer-1",
                    name: "artwork.png",
                    imagePath: "/tmp/artwork.png",
                    visible: true,
                    translateXMm: 2.5,
                    translateYMm: -1.25,
                    rotationDeg: 12,
                    scale: 0.8
                )
            ],
            outputs: ProjectOutputs(
                outputPath: "/tmp/out.iso",
                writeCue: false,
                dataDirectory: "",
                volumeLabel: "TEST_DISC",
                interleave: true,
                filesAtOuterRing: true,
                dvdReadCompatibility: true
            ),
            createdUtc: Date(timeIntervalSince1970: 1_761_000_000),
            modifiedUtc: Date(timeIntervalSince1970: 1_761_000_100),
            tone: ToneProfile(ditherStrength: 0.75, levels: 2, brightness: 4, srgbLinearization: true),
            bluRay: family == .bd ? ProjectBluRaySettings(invertMapping: true) : nil
        )
    }

    func testRoundTripThroughProjectStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscImageStudioTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("project.discproj")

        let document = sampleDocument(family: .dvd)
        try ProjectStore.save(document, to: url)
        let loaded = try ProjectStore.load(from: url)

        XCTAssertEqual(loaded.schemaVersion, 2)
        XCTAssertEqual(loaded.name, document.name)
        XCTAssertEqual(loaded.discFamily, "dvd")
        XCTAssertEqual(loaded.geometry, document.geometry)
        XCTAssertEqual(loaded.layers, document.layers)
        XCTAssertEqual(loaded.outputs, document.outputs)
        XCTAssertEqual(loaded.tone, document.tone)
        XCTAssertNil(loaded.bluRay)
        XCTAssertEqual(loaded.createdUtc.timeIntervalSince1970, 1_761_000_000, accuracy: 0.001)
    }

    func testBluRayRoundTripKeepsPolarity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscImageStudioTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("bd.discproj")

        try ProjectStore.save(sampleDocument(family: .bd), to: url)
        let loaded = try ProjectStore.load(from: url)
        XCTAssertEqual(loaded.family, .bd)
        XCTAssertEqual(loaded.bluRay?.invertMapping, true)
    }

    func testDecoderAcceptsFractionalSecondTimestampsFromDotNet() throws {
        let json = """
        {
          "schemaVersion": 2,
          "name": "DotNet Time",
          "discFamily": "cd",
          "geometry": {
            "innerRadiusMm": 24.5,
            "outerRadiusMm": 56.8,
            "sectors": 359849,
            "pitchLinear": 0,
            "pitchQuadratic": 0,
            "pitchCubic": 0,
            "usableSectors": 359847
          },
          "layers": [],
          "outputs": {
            "outputPath": "/tmp/out.wav",
            "writeCue": true,
            "dataDirectory": "",
            "volumeLabel": "CD_IMAGE",
            "interleave": true
          },
          "calibrationSessionPath": null,
          "thumbnailPngBase64": null,
          "createdUtc": "2026-08-23T03:40:14.1234567+00:00",
          "modifiedUtc": "2026-08-23T03:40:15.7654321+00:00",
          "tone": {
            "ditherStrength": 0.75,
            "levels": 2,
            "brightness": 0,
            "srgbLinearization": false
          }
        }
        """
        let document = try ProjectJSON.decoder.decode(ProjectDocument.self, from: Data(json.utf8))
        XCTAssertEqual(document.name, "DotNet Time")
        XCTAssertEqual(document.createdUtc.timeIntervalSince1970, 1_787_456_414.123, accuracy: 0.01)
        try document.validate()
    }

    func testProjectRejectsBluRaySettingsOnDvd() {
        var document = sampleDocument(family: .dvd)
        document.bluRay = ProjectBluRaySettings(invertMapping: true)
        XCTAssertThrowsError(try document.validate())
    }

    func testGeometryRejectsUnalignedBluRaySectors() {
        var geometry = DiscFamily.bd.defaultGeometry
        geometry.sectors = 12_219_391
        XCTAssertThrowsError(try geometry.validate(family: .bd))
    }

    func testGeometryContentOuterRadiusMatchesConstantPitchModel() {
        var geometry = DiscFamily.dvd.defaultGeometry
        geometry.usableSectors = geometry.sectors / 2
        let outer = geometry.contentOuterRadiusMm(family: .dvd)
        let expected = sqrt(
            geometry.innerRadiusMm * geometry.innerRadiusMm
                + 0.5 * (geometry.outerRadiusMm * geometry.outerRadiusMm - geometry.innerRadiusMm * geometry.innerRadiusMm)
        )
        XCTAssertEqual(outer, expected, accuracy: 0.000_001)
    }
}

final class ToneProfileTests: XCTestCase {
    func testLegacyBinaryMatchesHardThreshold() {
        let tone = ToneProfile.legacyBinary
        for gray in stride(from: 0, through: 255, by: 17) {
            XCTAssertEqual(tone.quantizedGray(gray: UInt8(gray), sampleIndex: Int64(gray)), gray >= 128 ? 255 : 0)
        }
    }

    func testDitherPhaseIsDeterministicAndInRange() {
        for index in [Int64(0), 1, 2, 42, 1_000_000, -5] {
            let value = ToneProfile.phase(index)
            XCTAssertEqual(value, ToneProfile.phase(index))
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
        XCTAssertNotEqual(ToneProfile.phase(1), ToneProfile.phase(2))
    }

    func testAdjustedGrayExtremes() {
        XCTAssertEqual(ToneProfile.legacyBinary.adjustedGray(0), 0)
        XCTAssertEqual(ToneProfile.legacyBinary.adjustedGray(255), 255)
        XCTAssertEqual(ToneProfile(ditherStrength: 0, brightness: 64).adjustedGray(255), 255)
        XCTAssertEqual(ToneProfile(ditherStrength: 0, brightness: -64).adjustedGray(0), 0)
    }

    func testFourLevelPaletteUsesNominalSteps() {
        let tone = ToneProfile(ditherStrength: 0, levels: 4)
        XCTAssertEqual(tone.quantizedGray(gray: 0, sampleIndex: 0), 0)
        XCTAssertEqual(tone.quantizedGray(gray: 100, sampleIndex: 0), 85)
        XCTAssertEqual(tone.quantizedGray(gray: 150, sampleIndex: 0), 170)
        XCTAssertEqual(tone.quantizedGray(gray: 250, sampleIndex: 0), 255)
    }
}

final class CLICommandBuilderTests: XCTestCase {
    private func state(family: DiscFamily) -> ProjectState {
        ProjectState(
            name: "CLI Test",
            family: family,
            geometry: family.defaultGeometry,
            layers: [ProjectLayer(name: "test.png", imagePath: "/tmp/test.png")],
            outputs: ProjectOutputs(
                outputPath: "/tmp/output.\(family.defaultOutputExtension)",
                dataDirectory: "",
                volumeLabel: "TEST",
                interleave: true
            ),
            tone: ToneProfile(ditherStrength: 0.75, levels: family == .cd ? 4 : 2, brightness: 3),
            invertMapping: true
        )
    }

    private func value(of option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    func testCDArgumentsCarryGeometryAndTone() throws {
        let state = state(family: .cd)
        let arguments = try CLICommandBuilder.exportArguments(
            state: state,
            compositeURL: URL(fileURLWithPath: "/tmp/composite.png")
        )
        XCTAssertEqual(arguments.first, "cd-generate")
        XCTAssertEqual(value(of: "--input", in: arguments), "/tmp/composite.png")
        XCTAssertEqual(value(of: "--sectors", in: arguments), "359849")
        XCTAssertEqual(value(of: "--usable-sectors", in: arguments), "359847")
        XCTAssertEqual(value(of: "--tone-levels", in: arguments), "4")
        XCTAssertEqual(value(of: "--tone-dither", in: arguments), "0.75")
        XCTAssertEqual(value(of: "--cue", in: arguments), "true")
        XCTAssertEqual(value(of: "--interleave", in: arguments), "true")
    }

    func testDVDArgumentsUseFillSectorsWithoutDataFolder() throws {
        var state = state(family: .dvd)
        state.outputs.dvdReadCompatibility = true
        let arguments = try CLICommandBuilder.exportArguments(
            state: state,
            compositeURL: URL(fileURLWithPath: "/tmp/composite.png")
        )
        XCTAssertEqual(arguments.first, "solve")
        XCTAssertEqual(value(of: "--iso-output", in: arguments), "/tmp/output.iso")
        XCTAssertEqual(value(of: "--fill-sectors", in: arguments), "2295104")
        XCTAssertEqual(value(of: "--read-compatibility", in: arguments), "true")
        XCTAssertNil(value(of: "--data-dir", in: arguments))
    }

    func testDVDHybridOmitsFillSectors() throws {
        var state = state(family: .dvd)
        state.outputs.dataDirectory = "/tmp/files"
        state.outputs.filesAtOuterRing = true
        let arguments = try CLICommandBuilder.exportArguments(
            state: state,
            compositeURL: URL(fileURLWithPath: "/tmp/composite.png")
        )
        XCTAssertNil(value(of: "--fill-sectors", in: arguments))
        XCTAssertEqual(value(of: "--data-dir", in: arguments), "/tmp/files")
        XCTAssertEqual(value(of: "--file-position", in: arguments), "outer")
    }

    func testBluRayArgumentsCarryPolarityAndUsableSectors() throws {
        let state = state(family: .bd)
        let arguments = try CLICommandBuilder.exportArguments(
            state: state,
            compositeURL: URL(fileURLWithPath: "/tmp/composite.png")
        )
        XCTAssertEqual(arguments.first, "bd-generate")
        XCTAssertEqual(value(of: "--invert", in: arguments), "true")
        XCTAssertEqual(value(of: "--usable-sectors", in: arguments), "12219392")
        XCTAssertEqual(value(of: "--tone-levels", in: arguments), "2")
    }

    func testNumberFormattingIsInvariant() {
        XCTAssertEqual(CLICommandBuilder.number(24.5), "24.5")
        XCTAssertEqual(CLICommandBuilder.number(0.000_001), "0.000001")
        XCTAssertEqual(CLICommandBuilder.number(-3.9256854319227684e-05), "-0.000039257")
    }
}

final class DesignRendererTests: XCTestCase {
    private func makeImage(at url: URL, size: Int = 64, color: (CGFloat, CGFloat, CGFloat, CGFloat) = (1, 0.2, 0.1, 1)) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw DesignRenderError.cannotCreateContext
        }
        context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: color.3))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = context.makeImage() else { throw DesignRenderError.cannotCreateContext }
        try DesignRenderer.writePNG(image, to: url)
    }

    func testCompositeRendersLayerAndThumbnail() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesignRendererTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("layer.png")
        try makeImage(at: imageURL)

        let layers = [ProjectLayer(name: "layer", imagePath: imageURL.path)]
        let composite = try DesignRenderer.renderComposite(layers: layers, outerRadiusMm: 58, outputSize: 256)
        XCTAssertEqual(composite.width, 256)
        XCTAssertEqual(composite.height, 256)
        XCTAssertNotNil(DesignRenderer.thumbnailBase64(layers: layers, outerRadiusMm: 58))
    }

    func testTonePreviewMasksHubAndOutsideDisc() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesignRendererTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("layer.png")
        try makeImage(at: imageURL, color: (0.5, 0.5, 0.5, 1))
        let composite = try DesignRenderer.renderComposite(
            layers: [ProjectLayer(name: "layer", imagePath: imageURL.path)],
            outerRadiusMm: 58,
            outputSize: 256
        )
        let preview = try DesignRenderer.renderDiscPreview(
            composite: composite,
            family: .dvd,
            geometry: DiscFamily.dvd.defaultGeometry,
            tone: ToneProfile(ditherStrength: 0, levels: 2),
            invertMapping: false,
            size: 256
        )
        guard let provider = preview.dataProvider, let data = provider.data,
              let pointer = CFDataGetBytePtr(data)
        else { return XCTFail("no preview pixels") }
        let center = (128 * preview.bytesPerRow) + (128 * 4)
        let outerCorner = 2 * preview.bytesPerRow + (2 * 4)
        let ring = (128 * preview.bytesPerRow) + (30 * 4)
        XCTAssertEqual(pointer[center + 3], 0, "hub must be transparent")
        XCTAssertEqual(pointer[outerCorner + 3], 0, "outside the disc must be transparent")
        XCTAssertEqual(pointer[ring + 3], 255, "recordable ring must be opaque")
    }
}

final class PresetCatalogTests: XCTestCase {
    func testBundledPresetsLoadedForEveryFamily() {
        XCTAssertGreaterThanOrEqual(PresetCatalog.presets(for: .cd).count, 4)
        XCTAssertGreaterThanOrEqual(PresetCatalog.presets(for: .dvd).count, 8)
        XCTAssertGreaterThanOrEqual(PresetCatalog.presets(for: .bd).count, 5)
    }

    func testStandardPresetsMatchEngineDefaults() {
        let cd = PresetCatalog.preset(id: "cd-80")
        XCTAssertEqual(cd?.geometry.sectors, 359_849)
        XCTAssertEqual(cd?.geometry.usableSectors, 359_847)
        let dvd = PresetCatalog.preset(id: "dvd-5-120mm")
        XCTAssertEqual(dvd?.geometry.sectors, 2_295_104)
        let bd = PresetCatalog.preset(id: "bd-r-sl-25gb")
        XCTAssertEqual(bd?.geometry.sectors, 12_219_392)
    }
}

final class CLIIntegrationTests: XCTestCase {
    func testTinyCDFromCompositeThroughEngine() async throws {
        guard let invocation = CLIService.shared.locateCLI() else {
            throw XCTSkip("disc-image-studio CLI is not available in this environment")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CLIIntegrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 64,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return XCTFail("context") }
        context.setFillColor(gray: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        guard let layerImage = context.makeImage() else { return XCTFail("image") }
        let layerURL = directory.appendingPathComponent("layer.png")
        try DesignRenderer.writePNG(layerImage, to: layerURL)

        var geometry = DiscFamily.cd.defaultGeometry
        geometry.sectors = 2
        geometry.usableSectors = 2
        let outputURL = directory.appendingPathComponent("test.wav")
        let state = ProjectState(
            name: "Integration",
            family: .cd,
            geometry: geometry,
            layers: [ProjectLayer(name: "layer", imagePath: layerURL.path)],
            outputs: ProjectOutputs(
                outputPath: outputURL.path,
                writeCue: true,
                dataDirectory: "",
                volumeLabel: "TEST",
                interleave: true
            ),
            tone: .photo
        )
        let compositeURL = directory.appendingPathComponent("composite.png")
        let composite = try DesignRenderer.renderComposite(
            layers: state.layers,
            outerRadiusMm: state.contentOuterRadiusMm,
            outputSize: 128
        )
        try DesignRenderer.writePNG(composite, to: compositeURL)

        let arguments = try CLICommandBuilder.exportArguments(state: state, compositeURL: compositeURL)
        let result = try await CLIService.shared.run(invocation, arguments: arguments)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 44)
        XCTAssertTrue(result.standardOutput.contains("CD track complete"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: outputURL.deletingPathExtension().appendingPathExtension("cue").path
        ))
    }

    func testTinyDVDAndBluRayThroughEngine() async throws {
        guard let invocation = CLIService.shared.locateCLI() else {
            throw XCTSkip("disc-image-studio CLI is not available in this environment")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CLIFormatTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 96,
            height: 96,
            bitsPerComponent: 8,
            bytesPerRow: 96 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return XCTFail("context") }
        context.setFillColor(CGColor(red: 0.8, green: 0.55, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
        guard let layerImage = context.makeImage() else { return XCTFail("image") }
        let layerURL = directory.appendingPathComponent("layer.png")
        try DesignRenderer.writePNG(layerImage, to: layerURL)

        for family in [DiscFamily.dvd, DiscFamily.bd] {
            var geometry = family.defaultGeometry
            geometry.sectors = family == .bd ? 32 : 16
            geometry.usableSectors = geometry.sectors
            let outputURL = directory.appendingPathComponent("test.\(family.rawValue).iso")
            let state = ProjectState(
                name: "Integration \(family.label)",
                family: family,
                geometry: geometry,
                layers: [ProjectLayer(name: "layer", imagePath: layerURL.path)],
                outputs: ProjectOutputs(outputPath: outputURL.path, dataDirectory: ""),
                tone: .photo
            )
            let compositeURL = directory.appendingPathComponent("composite-\(family.rawValue).png")
            let composite = try DesignRenderer.renderComposite(
                layers: state.layers,
                outerRadiusMm: state.contentOuterRadiusMm,
                outputSize: 128
            )
            try DesignRenderer.writePNG(composite, to: compositeURL)
            let arguments = try CLICommandBuilder.exportArguments(state: state, compositeURL: compositeURL)
            _ = try await CLIService.shared.run(invocation, arguments: arguments)
            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            XCTAssertGreaterThan(size, 0, "\(family.label) should produce an image")
        }
    }
}

@MainActor
final class WorkspaceViewModelTests: XCTestCase {
    func testCreateProjectWritesALoadableFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recentURL = directory.appendingPathComponent("recent.json")
        let model = WorkspaceViewModel(recentStore: RecentProjectsStore(fileURL: recentURL))
        let projectURL = directory.appendingPathComponent("Created.discproj")
        let outputURL = directory.appendingPathComponent("Created.iso")
        try model.createProject(
            name: "Created in test",
            family: .dvd,
            geometry: DiscFamily.dvd.defaultGeometry,
            invertMapping: false,
            projectURL: projectURL,
            outputURL: outputURL
        )

        XCTAssertTrue(model.hasProject)
        XCTAssertFalse(model.isDirty)
        let document = try ProjectStore.load(from: projectURL)
        XCTAssertEqual(document.name, "Created in test")
        XCTAssertEqual(document.family, .dvd)
        XCTAssertEqual(document.outputs.outputPath, outputURL.path)
        XCTAssertNotNil(document.tone)
        XCTAssertEqual(model.recentProjects.first?.projectPath, projectURL.path)
    }
}
