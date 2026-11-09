import Foundation

public struct CLIInvocation: Equatable, Sendable {
    public let executableURL: URL
    public let prefixArguments: [String]
    public let displayName: String
    public let source: String

    public init(executableURL: URL, prefixArguments: [String] = [], displayName: String, source: String) {
        self.executableURL = executableURL
        self.prefixArguments = prefixArguments
        self.displayName = displayName
        self.source = source
    }
}

public struct CLIResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let duration: TimeInterval

    public var succeeded: Bool { exitCode == 0 }

    public var combinedOutput: String {
        [standardOutput, standardError]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }
}

public enum CLIError: LocalizedError {
    case notFound
    case launchFailed(String)
    case failed(exitCode: Int32, output: String)
    case missingOutput(String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "The disc engine CLI was not found. Build it with `dotnet build src/DiscImageStudio.Cli -c Release`, or choose it in Settings."
        case .launchFailed(let message):
            return "Could not launch the disc engine: \(message)"
        case .failed(let exitCode, let output):
            let tail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return tail.isEmpty
                ? "The disc engine exited with code \(exitCode)."
                : "The disc engine exited with code \(exitCode):\n\(tail)"
        case .missingOutput(let path):
            return "The disc engine completed but did not write \(path)."
        }
    }
}

/// Locates and runs the cross-platform `disc-image-studio` CLI that owns the physical
/// disc encoders. Native UI work stays in Swift; bit-level generation stays in .NET.
public final class CLIService: @unchecked Sendable {
    public static let shared = CLIService()
    public static let customPathDefaultsKey = "DISCImageStudioCLIPath"

    private let lock = NSLock()
    private var currentProcess: Process?

    public init() {}

    // MARK: - Discovery

    public func locateCLI(customPath: String? = nil) -> CLIInvocation? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [(String, String)] = []

        if let env = environment["DIS_IMAGE_STUDIO_CLI"], !env.isEmpty {
            candidates.append((env, "environment"))
        }
        if let customPath, !customPath.isEmpty {
            candidates.append((customPath, "settings"))
        }
        if let saved = UserDefaults.standard.string(forKey: CLIService.customPathDefaultsKey), !saved.isEmpty {
            candidates.append((saved, "settings"))
        }

        let bundleResources = Bundle.main.resourceURL
        if let bundleResources {
            // Prefer the managed DLL when a .NET host is available; apphosts only find
            // runtimes in well-known locations, while `dotnet <dll>` always works.
            candidates.append((bundleResources.appendingPathComponent("cli/disc-image-studio.dll").path, "app bundle"))
            candidates.append((bundleResources.appendingPathComponent("cli/disc-image-studio").path, "app bundle"))
            candidates.append((bundleResources.appendingPathComponent("disc-image-studio").path, "app bundle"))
        }

        #if DEBUG
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // Kit
            .deletingLastPathComponent() // DiscImageStudioMac
            .deletingLastPathComponent() // macos
            .deletingLastPathComponent() // repository root
        let cliRoot = sourceRoot
            .appendingPathComponent("src/DiscImageStudio.Cli/bin")
        for configuration in ["Release", "Debug"] {
            candidates.append((cliRoot.appendingPathComponent("\(configuration)/net10.0/disc-image-studio.dll").path, "developer build"))
            candidates.append((cliRoot.appendingPathComponent("\(configuration)/net10.0/disc-image-studio").path, "developer build"))
        }
        #endif

        candidates.append(("/opt/homebrew/bin/disc-image-studio", "Homebrew"))
        candidates.append(("/usr/local/bin/disc-image-studio", "Homebrew"))
        candidates.append((FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/disc-image-studio").path, "user install"))

        let fileManager = FileManager.default
        for (path, source) in candidates {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            if url.pathExtension.lowercased() == "dll" {
                if let dotnet = findDotnet() {
                    return CLIInvocation(
                        executableURL: dotnet,
                        prefixArguments: [url.path],
                        displayName: "disc-image-studio (dotnet)",
                        source: source
                    )
                }
                continue
            }
            if fileManager.isExecutableFile(atPath: url.path) {
                return CLIInvocation(
                    executableURL: url,
                    displayName: "disc-image-studio",
                    source: source
                )
            }
        }

        // Last resort: a `disc-image-studio` executable on PATH.
        if let path = which("disc-image-studio") {
            return CLIInvocation(executableURL: URL(fileURLWithPath: path), displayName: path, source: "PATH")
        }
        return nil
    }

    public func detectionSummary(customPath: String? = nil) -> String {
        guard let invocation = locateCLI(customPath: customPath) else {
            return "Not found — build the CLI or choose a path in Settings."
        }
        var text = invocation.executableURL.path
        if !invocation.prefixArguments.isEmpty {
            text += " " + invocation.prefixArguments.joined(separator: " ")
        }
        return "\(text) (\(invocation.source))"
    }

    private func findDotnet() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".dotnet/dotnet").path,
            "/opt/homebrew/bin/dotnet",
            "/usr/local/bin/dotnet",
            "/usr/bin/dotnet"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let path = which("dotnet") {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func which(_ tool: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [tool]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        } catch {
            return nil
        }
    }

    // MARK: - Run

    public func run(
        _ invocation: CLIInvocation,
        arguments: [String],
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws -> CLIResult {
        try await Task.detached(priority: .userInitiated) { [self] in
            let process = Process()
            process.executableURL = invocation.executableURL
            process.arguments = invocation.prefixArguments + arguments
            var environment = ProcessInfo.processInfo.environment
            environment["DOTNET_NOLOGO"] = "1"
            environment["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
            if invocation.executableURL.lastPathComponent != "dotnet",
               environment["DOTNET_ROOT"] == nil,
               let dotnet = findDotnet() {
                environment["DOTNET_ROOT"] = dotnet.deletingLastPathComponent().path
            }
            process.environment = environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = FileHandle.nullDevice

            let collector = OutputCollector(progress: progress)
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                collector.append(handle.availableData, isError: false)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                collector.append(handle.availableData, isError: true)
            }

            let started = Date()
            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                throw CLIError.launchFailed(error.localizedDescription)
            }

            lock.lock()
            currentProcess = process
            lock.unlock()

            process.waitUntilExit()

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            collector.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile(), isError: false)
            collector.append(stderrPipe.fileHandleForReading.readDataToEndOfFile(), isError: true)

            lock.lock()
            currentProcess = nil
            lock.unlock()

            let result = CLIResult(
                exitCode: process.terminationStatus,
                standardOutput: collector.output,
                standardError: collector.error,
                duration: Date().timeIntervalSince(started)
            )
            guard result.succeeded else {
                throw CLIError.failed(exitCode: result.exitCode, output: result.combinedOutput)
            }
            return result
        }.value
    }

    public func cancelCurrent() {
        lock.lock()
        let process = currentProcess
        lock.unlock()
        process?.terminate()
    }

    public func isRunning() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentProcess?.isRunning ?? false
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let progress: (@Sendable (String) -> Void)?
    private var stdout = Data()
    private var stderr = Data()

    init(progress: (@Sendable (String) -> Void)?) {
        self.progress = progress
    }

    func append(_ data: Data, isError: Bool) {
        guard !data.isEmpty else { return }
        lock.lock()
        if isError {
            stderr.append(data)
        } else {
            stdout.append(data)
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                progress?(text)
            }
        }
        lock.unlock()
    }

    var output: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: stdout, as: UTF8.self)
    }

    var error: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: stderr, as: UTF8.self)
    }
}
