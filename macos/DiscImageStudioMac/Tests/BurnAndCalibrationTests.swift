import XCTest
@testable import DiscImageStudioKit

final class BurnServiceDeviceTests: XCTestCase {
    private let sampleList = """
    Vendor   Product              Rev    Bus    Support
    0        HL-DT-ST DVDRAM GP08NU6B   1.00   USB    Unsupported
    1        MATSHITA DVD-RAM UJ8E2    1.10   SATA   Full
    """

    func testParseDevicesSkipsHeaderAndReadsBothDrives() {
        let devices = BurnService.parseDevices(sampleList)

        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices.map(\.index), [0, 1])

        XCTAssertEqual(devices[0].name, "HL-DT-ST DVDRAM GP08NU6B")
        XCTAssertEqual(devices[0].firmware, "1.00")
        XCTAssertEqual(devices[0].bus, "USB")
        XCTAssertEqual(devices[0].support, "Unsupported")

        XCTAssertEqual(devices[1].name, "MATSHITA DVD-RAM UJ8E2")
        XCTAssertEqual(devices[1].firmware, "1.10")
        XCTAssertEqual(devices[1].bus, "SATA")
        XCTAssertEqual(devices[1].support, "Full")
    }

    func testSplitRunsKeepsSingleSpacesInsideFields() {
        let fields = BurnService.splitRuns(
            "0   HL-DT-ST DVDRAM GP08NU6B   1.00  USB   Unsupported"
        )

        XCTAssertEqual(
            fields,
            ["0", "HL-DT-ST DVDRAM GP08NU6B", "1.00", "USB", "Unsupported"]
        )
    }
}

final class BurnServiceArgumentTests: XCTestCase {
    func testAudioBurnArgumentsCarryDeviceAndExplicitOptions() {
        let artifactURL = URL(fileURLWithPath: "/tmp/audio-burn.wav")
        let options = BurnOptions(testBurn: true, verify: false, eject: false, speed: "4")

        let arguments = BurnService.burnArguments(
            artifactURL: artifactURL,
            isAudio: true,
            deviceIndex: 1,
            options: options
        )

        XCTAssertEqual(
            arguments,
            [
                "-drive", "1",
                "burn",
                "-audio",
                "-test",
                "-noverify",
                "-noeject",
                "-speed", "4",
                artifactURL.path
            ]
        )
    }

    func testDataBurnArgumentsOmitDriveAndUseDefaults() {
        let artifactURL = URL(fileURLWithPath: "/tmp/data-burn.iso")

        let arguments = BurnService.burnArguments(
            artifactURL: artifactURL,
            isAudio: false,
            deviceIndex: nil,
            options: BurnOptions()
        )

        XCTAssertEqual(
            arguments,
            ["burn", "-data", "-notest", "-verify", "-eject", artifactURL.path]
        )
        XCTAssertFalse(arguments.contains("-drive"))
        XCTAssertFalse(arguments.contains("-speed"))
    }

    func testAudioArtifactDetectionIsCaseInsensitive() {
        XCTAssertTrue(BurnService.isAudioArtifact(URL(fileURLWithPath: "/tmp/track.wav")))
        XCTAssertTrue(BurnService.isAudioArtifact(URL(fileURLWithPath: "/tmp/TRACK.WAV")))
        XCTAssertFalse(BurnService.isAudioArtifact(URL(fileURLWithPath: "/tmp/image.iso")))
    }
}

final class CalibrationStageTests: XCTestCase {
    func testStagesCoverBoundaryAndFineWithInstructions() {
        XCTAssertTrue(CalibrationStage.allCases.contains(.boundary))
        XCTAssertTrue(CalibrationStage.allCases.contains(.fine))

        for stage in [CalibrationStage.boundary, CalibrationStage.fine] {
            XCTAssertFalse(
                stage.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(stage.rawValue) should have instructions"
            )
        }
    }
}

final class CalibrationJSONRoundTripTests: XCTestCase {
    private func assertRoundTrip<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let data = try ProjectJSON.encoder.encode(value)
        let decoded = try ProjectJSON.decoder.decode(T.self, from: data)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }

    func testCalibrationResultsRoundTripThroughProjectJSON() throws {
        let targetInfo = CalibrationTargetInfo(
            targetId: "target-001",
            kind: "dvd",
            stage: CalibrationStage.boundary.rawValue,
            innerRadiusMm: 24,
            outerRadiusMm: 58,
            sectors: 2_295_104,
            usableSectors: 2_295_000,
            pitchLinear: 0.000_1,
            pitchQuadratic: 0,
            pitchCubic: 0,
            drawingInnerRadiusMm: 25,
            drawingOuterRadiusMm: 57,
            previewPath: "/tmp/target-preview.png",
            burnImagePath: "/tmp/target-burn.iso",
            sessionPath: "/tmp/calibration-session",
            previewSize: 1_200,
            burnImageSize: 2_048
        )

        let rectifyResult = CalibrationRectifyResult(
            succeeded: true,
            message: "Rectified the photo",
            outerRmsPixels: 0.42,
            holeRmsPixels: 0.18,
            canvasOuterRadiusMm: 63,
            pixelSize: 1_200,
            output: "/tmp/rectified.png"
        )

        let parameters = CalibrationParametersDTO(
            kind: "dvd",
            innerRadiusMm: 24.1,
            outerRadiusMm: 58.2,
            sectors: 2_295_104,
            usableSectors: 2_295_000,
            pitchLinear: 0.000_2,
            pitchQuadratic: -0.000_001,
            pitchCubic: 0,
            invertMapping: false
        )
        let candidate = CalibrationCandidateDTO(
            parameters: parameters,
            rotationRadians: 0.125,
            rmsErrorMm: 0.031,
            robustCost: 0.042,
            maxErrorMm: 0.09,
            outlierCount: 2
        )
        let solveResult = CalibrationSolveResult(
            succeeded: true,
            reliable: true,
            boundaryLimited: false,
            requiresShapeConfirmation: false,
            rotationRadians: 0.125,
            rmsErrorMm: 0.031,
            warnings: ["One point rejected as an outlier"],
            best: parameters,
            candidates: [candidate]
        )

        try assertRoundTrip(targetInfo)
        try assertRoundTrip(rectifyResult)
        try assertRoundTrip(solveResult)
    }
}

final class CalibrationCoordinateTests: XCTestCase {
    /// Mirrors the rectified-pixel-to-millimetre conversion in `CalibrationViewModel.solve()`.
    private func millimetres(
        pixelX: Double,
        pixelY: Double,
        pixelSize: Int,
        canvasOuterRadiusMm: Double
    ) -> (x: Double, y: Double) {
        let mmPerPixel = 2 * canvasOuterRadiusMm / Double(max(1, pixelSize))
        let centre = Double(pixelSize) / 2
        return ((pixelX - centre) * mmPerPixel, (pixelY - centre) * mmPerPixel)
    }

    func testCentreAndEdgePixelsMapToExpectedMillimetres() {
        let pixelSize = 1_000
        let canvasRadiusMm = 60.0

        let centre = millimetres(
            pixelX: 500,
            pixelY: 500,
            pixelSize: pixelSize,
            canvasOuterRadiusMm: canvasRadiusMm
        )
        XCTAssertEqual(centre.x, 0, accuracy: 1e-9)
        XCTAssertEqual(centre.y, 0, accuracy: 1e-9)

        let rightEdge = millimetres(
            pixelX: 1_000,
            pixelY: 500,
            pixelSize: pixelSize,
            canvasOuterRadiusMm: canvasRadiusMm
        )
        XCTAssertEqual(rightEdge.x, canvasRadiusMm, accuracy: 1e-9)
        XCTAssertEqual(rightEdge.y, 0, accuracy: 1e-9)

        let oppositeEdge = millimetres(
            pixelX: 0,
            pixelY: 0,
            pixelSize: pixelSize,
            canvasOuterRadiusMm: canvasRadiusMm
        )
        XCTAssertEqual(oppositeEdge.x, -canvasRadiusMm, accuracy: 1e-9)
        XCTAssertEqual(oppositeEdge.y, -canvasRadiusMm, accuracy: 1e-9)

        let quarter = millimetres(
            pixelX: 750,
            pixelY: 250,
            pixelSize: pixelSize,
            canvasOuterRadiusMm: canvasRadiusMm
        )
        XCTAssertEqual(quarter.x, 30, accuracy: 1e-9)
        XCTAssertEqual(quarter.y, -30, accuracy: 1e-9)
    }
}
