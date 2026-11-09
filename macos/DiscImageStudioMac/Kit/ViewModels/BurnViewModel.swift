import Combine
import Foundation

@MainActor
public final class BurnViewModel: ObservableObject {
    @Published public private(set) var devices: [OpticalDevice] = []
    @Published public var selectedDeviceID: Int?
    @Published public private(set) var media: OpticalMediaStatus?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var isBurning = false
    @Published public private(set) var statusText = "Insert a blank disc, then refresh."
    @Published public private(set) var log = ""
    @Published public var options = BurnOptions()

    private let cliService: CLIService
    private var burnTask: Task<Void, Never>?

    public init(cliService: CLIService = .shared) {
        self.cliService = cliService
    }

    public var selectedDevice: OpticalDevice? {
        guard let selectedDeviceID else { return nil }
        return devices.first { $0.index == selectedDeviceID }
    }

    public var canBurn: Bool {
        selectedDevice != nil && media?.present == true && !isBurning
    }

    public var mediaWarning: String? {
        guard let media else { return "Media state has not been read yet." }
        if !media.present { return "Insert a blank CD-R, DVD-R or BD-R." }
        if !media.isBlank { return "The disc may not be blank. Write-once media cannot be reused; verify before burning." }
        return nil
    }

    public func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusText = "Scanning optical drives…"
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                BurnService.listDevices()
            }.value
            devices = found
            if let selectedDeviceID, !found.contains(where: { $0.index == selectedDeviceID }) {
                self.selectedDeviceID = nil
            }
            if selectedDeviceID == nil {
                selectedDeviceID = found.first?.index
            }
            isRefreshing = false
            if found.isEmpty {
                media = nil
                statusText = "No optical drive detected. Connect a USB or internal burner."
            } else {
                refreshMedia()
            }
        }
    }

    public func refreshMedia() {
        guard let device = selectedDevice else {
            media = nil
            statusText = "Choose an optical drive."
            return
        }
        statusText = "Reading media in \(device.name)…"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                BurnService.status(deviceIndex: device.index)
            }.value
            media = result
            statusText = result.present
                ? "\(device.name): \(result.summary)"
                : "\(device.name): no media inserted"
        }
    }

    public func eject() {
        guard let device = selectedDevice else { return }
        let result = BurnService.eject(deviceIndex: device.index)
        switch result {
        case .success:
            statusText = "Tray ejected."
        case .failure(let error):
            statusText = error.localizedDescription
        }
        refreshMedia()
    }

    public func burn(
        artifactURL: URL,
        family: DiscFamily,
        confirmNonBlank: Bool = false
    ) {
        guard !isBurning else { return }
        guard let device = selectedDevice else {
            statusText = BurnError.noDevice.localizedDescription
            return
        }
        guard FileManager.default.fileExists(atPath: artifactURL.path) else {
            statusText = BurnError.missingArtifact(artifactURL.path).localizedDescription
            return
        }
        guard let media, media.present else {
            statusText = BurnError.noMedia.localizedDescription
            return
        }
        if !media.isBlank && !confirmNonBlank {
            statusText = "The media does not look blank. Confirm the warning before burning."
            return
        }

        isBurning = true
        log = ""
        statusText = options.testBurn ? "Running a test burn (laser off)…" : "Burning \(artifactURL.lastPathComponent)…"
        appendLog("Artifact: \(artifactURL.path)\n")
        appendLog("Drive: \(device.name)\n")
        appendLog("Media: \(media.rawText.trimmingCharacters(in: .whitespacesAndNewlines))\n")

        burnTask = Task { [weak self] in
            guard let self else { return }
            var temporaryDirectory: URL?
            defer {
                if let temporaryDirectory {
                    try? FileManager.default.removeItem(at: temporaryDirectory)
                }
                self.isBurning = false
            }
            do {
                let isAudio = BurnService.isAudioArtifact(artifactURL)
                var burnURL = artifactURL
                if isAudio {
                    let directory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("DiscImageStudioBurn-\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    temporaryDirectory = directory
                    let linked = directory.appendingPathComponent(artifactURL.lastPathComponent)
                    do {
                        try FileManager.default.linkItem(at: artifactURL, to: linked)
                    } catch {
                        try FileManager.default.copyItem(at: artifactURL, to: linked)
                    }
                    burnURL = directory
                    self.appendLog("Audio source folder: \(directory.path)\n")
                }

                let arguments = BurnService.burnArguments(
                    artifactURL: artifactURL,
                    isAudio: isAudio,
                    deviceIndex: device.index,
                    options: self.options,
                    burnPathOverride: burnURL
                )
                self.appendLog("$ /usr/bin/drutil \(arguments.joined(separator: " "))\n")
                let invocation = CLIInvocation(
                    executableURL: URL(fileURLWithPath: BurnService.drutilPath),
                    displayName: "drutil",
                    source: "macOS DiscRecording"
                )
                let result = try await self.cliService.run(invocation, arguments: arguments) { chunk in
                    Task { @MainActor in
                        self.appendLog(chunk)
                    }
                }
                self.appendLog(result.combinedOutput)
                if self.options.testBurn {
                    self.statusText = "Test burn completed. Insert a blank disc and disable test mode to write."
                } else {
                    self.statusText = "Burn completed · \(artifactURL.lastPathComponent) · \(String(format: "%.1f", result.duration)) s"
                }
                if self.options.eject {
                    self.refreshMedia()
                }
            } catch {
                if Task.isCancelled {
                    self.statusText = BurnError.cancelled.localizedDescription
                } else {
                    self.statusText = error.localizedDescription
                }
                self.appendLog(error.localizedDescription + "\n")
            }
        }
    }

    public func cancel() {
        burnTask?.cancel()
        cliService.cancelCurrent()
        statusText = "Cancelling burn…"
    }

    private func appendLog(_ text: String) {
        guard !text.isEmpty else { return }
        log += text.hasSuffix("\n") ? text : text + "\n"
        if log.count > 160_000 {
            log = String(log.suffix(120_000))
        }
    }
}
