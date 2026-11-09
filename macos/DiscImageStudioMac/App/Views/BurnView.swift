import DiscImageStudioKit
import SwiftUI

struct BurnView: View {
    @ObservedObject var model: WorkspaceViewModel
    @StateObject private var burner = BurnViewModel()
    @State private var showConfirmation = false

    private let speeds = ["max", "1", "2", "4", "8", "16"]

    private var artifactURL: URL? {
        if let override = model.burnArtifactOverride {
            return override
        }
        guard let path = model.state?.outputs.outputPath, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private var artifactExists: Bool {
        guard let artifactURL else { return false }
        return FileManager.default.fileExists(atPath: artifactURL.path)
    }

    private var isAudio: Bool {
        guard let artifactURL else { return false }
        return BurnService.isAudioArtifact(artifactURL)
    }

    private var artifactKind: String {
        if isAudio { return "CD audio (WAV → Red Book)" }
        if model.family == .bd { return "BD-R data image (ISO)" }
        if model.family == .dvd { return "DVD data image (ISO)" }
        return "CD data image (ISO)"
    }

    var body: some View {
        HStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 12) {
                    sourceCard
                    driveCard
                    optionsCard
                    safetyCard
                }
                .padding(.trailing, 2)
            }
            .frame(width: 440)

            logPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .onAppear { burner.refresh() }
        .onChange(of: burner.selectedDeviceID) { _, _ in
            burner.refreshMedia()
        }
        .onChange(of: model.state?.outputs.outputPath) { _, _ in
            // Keep the current media reading; only the source row changes.
        }
        .alert("Burn this disc?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(burner.options.testBurn ? "Run test" : "Burn", role: .destructive) {
                guard let artifactURL else { return }
                burner.burn(
                    artifactURL: artifactURL,
                    family: model.family,
                    confirmNonBlank: true
                )
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var sourceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                SectionTitle(title: "Source", subtitle: "Generated artifact", icon: "shippingbox")
                if let artifactURL {
                    HStack(spacing: 8) {
                        Image(systemName: isAudio ? "waveform" : "externaldrive")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(artifactURL.lastPathComponent)
                                .font(.system(size: 12, weight: .semibold))
                            Text(artifactURL.path)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if model.burnArtifactOverride != nil {
                            Tag(text: "CALIBRATION", color: Theme.mint)
                        }
                        Tag(text: artifactExists ? "READY" : "MISSING", color: artifactExists ? Theme.mint : Theme.amber)
                    }
                    if model.burnArtifactOverride != nil {
                        Button("Use project export instead") { model.useBurnArtifact(nil) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                    }
                    LabeledValue(label: "Write mode", value: artifactKind)
                    if isAudio {
                        Text("macOS DiscRecording converts the WAV into a Red Book audio CD; the generated CUE remains available for other burners.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Choose an output path on the Export page first.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                if !artifactExists {
                    Button {
                        model.generateImage()
                    } label: {
                        Label("Generate artifact now", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .disabled(!model.canExport || model.isExporting)
                }
            }
        }
    }

    private var driveCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    SectionTitle(title: "Optical drive", subtitle: "Detected with DiscRecording", icon: "opticaldiscdrive")
                    Spacer()
                    Button {
                        burner.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh drives and media")
                }

                if burner.devices.isEmpty {
                    HStack(spacing: 9) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Theme.amber)
                        Text(burner.isRefreshing ? "Scanning…" : "No drive found. Connect a USB burner and refresh.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("", selection: $burner.selectedDeviceID) {
                        ForEach(burner.devices) { device in
                            Text(device.name).tag(Optional(device.index))
                        }
                    }
                    .labelsHidden()

                    if let device = burner.selectedDevice {
                        Text(device.detail)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill((burner.media?.present ?? false) ? (burner.media?.isBlank == true ? Theme.mint : Theme.amber) : .secondary)
                            .frame(width: 7, height: 7)
                        Text(burner.media.map(\.summary) ?? "Reading media…")
                            .font(.system(size: 10.5, weight: .medium))
                        Spacer()
                        Button("Refresh") { burner.refreshMedia() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                        Button("Eject") { burner.eject() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .disabled(burner.media?.present != true)
                    }

                    if let warning = burner.mediaWarning {
                        Text(warning)
                            .font(.system(size: 9.5))
                            .foregroundStyle(warning.contains("may not be blank") ? Theme.amber : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var optionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Burn options", subtitle: "Applied to the next write", icon: "slider.horizontal.3")
                Toggle("Test burn (laser off)", isOn: $burner.options.testBurn)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Toggle("Verify after burning", isOn: $burner.options.verify)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Toggle("Eject when finished", isOn: $burner.options.eject)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                HStack {
                    Text("Speed")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $burner.options.speed) {
                        ForEach(speeds, id: \.self) { speed in
                            Text(speed == "max" ? "Maximum" : "\(speed)×").tag(speed)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                HStack(spacing: 8) {
                    Button {
                        showConfirmation = true
                    } label: {
                        Label(burner.options.testBurn ? "Run test burn" : "Burn disc", systemImage: "flame")
                    }
                    .buttonStyle(PrimaryActionButtonStyle(tint: burner.options.testBurn ? Theme.mint : Theme.amber))
                    .disabled(!artifactExists || !burner.canBurn)
                    if burner.isBurning {
                        Button("Cancel") { burner.cancel() }
                            .buttonStyle(SecondaryActionButtonStyle())
                    }
                    Spacer()
                }
            }
        }
    }

    private var safetyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Media safety", systemImage: "exclamationmark.shield")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                Text("CD-R, DVD-R and BD-R are write-once. A failed or interrupted burn usually ruins the disc. Use only expendable media while testing, and keep the burner connected until the drive ejects or reports completion.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.family == .bd {
                    Text("macOS DiscRecording has limited Blu-ray writer support. Some BD-R drives and media will be rejected even though the ISO was generated correctly; use a supported drive or an external BD authoring tool.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var logPanel: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Burn log")
                            .font(.system(size: 12, weight: .semibold))
                        Text(burner.statusText)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if burner.isBurning {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(14)

                Divider().opacity(0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        if burner.log.isEmpty {
                            Text("Drive discovery and DiscRecording output appear here.")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(14)
                        } else {
                            Text(burner.log)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
            }
        }
    }

    private var confirmationMessage: String {
        let name = artifactURL?.lastPathComponent ?? "the generated image"
        if burner.options.testBurn {
            return "Run a test burn of \(name) with the laser disabled. No disc data will be written."
        }
        let media = burner.media?.summary ?? "the inserted disc"
        return "Write \(name) to \(media). This cannot be undone on write-once media."
    }
}
