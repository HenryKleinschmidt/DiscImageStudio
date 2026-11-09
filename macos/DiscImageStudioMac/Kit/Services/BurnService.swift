import Foundation

public struct OpticalDevice: Identifiable, Equatable, Sendable {
    public let index: Int
    public let vendor: String
    public let product: String
    public let firmware: String
    public let bus: String
    public let support: String

    public var id: Int { index }
    public var name: String {
        [vendor, product].filter { !$0.isEmpty }.joined(separator: " ")
    }
    public var detail: String {
        "Drive \(index) · \(bus) · firmware \(firmware) · \(support)"
    }

    public init(index: Int, vendor: String, product: String, firmware: String, bus: String, support: String) {
        self.index = index
        self.vendor = vendor
        self.product = product
        self.firmware = firmware
        self.bus = bus
        self.support = support
    }
}

public struct OpticalMediaStatus: Equatable, Sendable {
    public let present: Bool
    public let mediaType: String?
    public let isBlank: Bool
    public let rawText: String

    public var summary: String {
        if !present { return "No media inserted" }
        var parts: [String] = []
        if let mediaType { parts.append(mediaType) }
        parts.append(isBlank ? "blank" : "state unknown")
        return parts.joined(separator: " · ")
    }
}

public struct BurnOptions: Equatable, Sendable {
    public var testBurn: Bool
    public var verify: Bool
    public var eject: Bool
    public var speed: String

    public init(testBurn: Bool = false, verify: Bool = true, eject: Bool = true, speed: String = "max") {
        self.testBurn = testBurn
        self.verify = verify
        self.eject = eject
        self.speed = speed
    }
}

/// Wraps macOS DiscRecording's `drutil` command. `drutil burn -audio` accepts a
/// directory of audio files, while `-data` accepts an ISO/CUE image. It also works
/// with USB drives that macOS marks as "Unsupported" but which still implement MMC.
public enum BurnService {
    public static let drutilPath = "/usr/bin/drutil"

    public static func listDevices() -> [OpticalDevice] {
        guard let result = runSync(arguments: ["list"]), result.exitCode == 0 else { return [] }
        return parseDevices(result.output)
    }

    static func parseDevices(_ text: String) -> [OpticalDevice] {
        var devices: [OpticalDevice] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            if line.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("vendor") { continue }
            let fields = splitRuns(line)
            guard fields.count >= 5,
                  let index = Int(fields[0]),
                  fields[1].rangeOfCharacter(from: .letters) != nil
            else { continue }
            devices.append(
                OpticalDevice(
                    index: index,
                    vendor: fields[1],
                    product: "",
                    firmware: fields[2],
                    bus: fields[3],
                    support: fields[4]
                )
            )
        }
        return devices
    }

    /// Splits on runs of two or more spaces so product names with single spaces survive.
    static func splitRuns(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var spaces = 0
        for character in line {
            if character == " " {
                spaces += 1
                continue
            }
            if spaces >= 2, !current.isEmpty {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else if spaces > 0, !current.isEmpty {
                current.append(String(repeating: " ", count: spaces))
            }
            spaces = 0
            current.append(character)
        }
        if !current.isEmpty {
            fields.append(current.trimmingCharacters(in: .whitespaces))
        }
        return fields
    }

    public static func status(deviceIndex: Int) -> OpticalMediaStatus {
        guard let result = runSync(arguments: ["-drive", String(deviceIndex), "status"]),
              result.exitCode == 0
        else {
            return OpticalMediaStatus(present: false, mediaType: nil, isBlank: false, rawText: resultOutputFallback())
        }
        let text = result.output
        let lower = text.lowercased()
        let present = !lower.contains("no media inserted")
            && !lower.contains("please insert")
            && !lower.contains("kein medium")
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var mediaType: String?
        var isBlank = false
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowerLine = trimmed.lowercased()
            if lowerLine.hasPrefix("type:") {
                mediaType = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
            if lowerLine.contains("blank") && !lowerLine.contains("not blank")
                && !lowerLine.contains("non-blank") && !lowerLine.contains("notblank") {
                isBlank = true
            }
        }
        return OpticalMediaStatus(present: present, mediaType: mediaType, isBlank: isBlank, rawText: text)
    }

    public static func eject(deviceIndex: Int) -> Result<Void, Error> {
        guard let result = runSync(arguments: ["-drive", String(deviceIndex), "tray", "eject"]) else {
            return .failure(BurnError.toolMissing)
        }
        return result.exitCode == 0
            ? .success(())
            : .failure(BurnError.commandFailed(result.output))
    }

    /// Builds the `drutil burn` argument vector for a generated artifact.
    public static func burnArguments(
        artifactURL: URL,
        isAudio: Bool,
        deviceIndex: Int?,
        options: BurnOptions,
        burnPathOverride: URL? = nil
    ) -> [String] {
        var args: [String] = []
        if let deviceIndex {
            args += ["-drive", String(deviceIndex)]
        }
        args += ["burn"]
        args.append(isAudio ? "-audio" : "-data")
        args.append(options.testBurn ? "-test" : "-notest")
        args.append(options.verify ? "-verify" : "-noverify")
        args.append(options.eject ? "-eject" : "-noeject")
        if options.speed != "max" {
            args += ["-speed", options.speed]
        }
        args.append((burnPathOverride ?? artifactURL).path)
        return args
    }

    public static func isAudioArtifact(_ url: URL) -> Bool {
        ["wav", "aif", "aiff", "m4a", "mp3"].contains(url.pathExtension.lowercased())
    }

    // MARK: - Process helpers

    struct SyncResult {
        let exitCode: Int32
        let output: String
    }

    static func runSync(arguments: [String]) -> SyncResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: drutilPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return SyncResult(
                exitCode: process.terminationStatus,
                output: String(decoding: data, as: UTF8.self)
            )
        } catch {
            return nil
        }
    }

    private static func resultOutputFallback() -> String {
        "drutil is not available"
    }
}

public enum BurnError: LocalizedError {
    case toolMissing
    case noDevice
    case noMedia
    case missingArtifact(String)
    case commandFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .toolMissing:
            return "macOS DiscRecording (`/usr/bin/drutil`) is not available."
        case .noDevice:
            return "No optical drive was detected."
        case .noMedia:
            return "Insert a blank recordable disc first."
        case .missingArtifact(let path):
            return "The generated artifact does not exist: \(path). Generate it on the Export page first."
        case .commandFailed(let output):
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .cancelled:
            return "Burn cancelled."
        }
    }
}
