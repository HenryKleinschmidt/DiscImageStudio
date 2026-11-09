import AppKit
import DiscImageStudioKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: WorkspaceViewModel
    @ObservedObject private var settings: AppSettings
    @State private var isTesting = false
    @State private var testResult: String?

    init(model: WorkspaceViewModel) {
        self.model = model
        _settings = ObservedObject(wrappedValue: model.settings)
    }

    var body: some View {
        TabView {
            engineTab
                .tabItem { Label("Engine", systemImage: "terminal") }
            defaultsTab
                .tabItem { Label("Defaults", systemImage: "slider.horizontal.3") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(.top, 4)
    }

    private var engineTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(
                            title: "Disc engine",
                            subtitle: "The SwiftUI app calls the cross-platform .NET CLI",
                            icon: "terminal"
                        )
                        Text(model.cliDetection)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            TextField("Custom CLI path (optional)", text: $settings.cliPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 10.5, design: .monospaced))
                            Button("Choose…") { chooseCLI() }
                                .buttonStyle(SecondaryActionButtonStyle())
                        }

                        HStack(spacing: 8) {
                            Button {
                                testEngine()
                            } label: {
                                Label(isTesting ? "Testing…" : "Test engine", systemImage: "play.circle")
                            }
                            .buttonStyle(SecondaryActionButtonStyle())
                            .disabled(isTesting)

                            Button("Auto-detect") {
                                settings.resetCLIPath()
                                model.refreshCLIDetection()
                                testResult = nil
                            }
                            .buttonStyle(SecondaryActionButtonStyle())

                            if let testResult {
                                Text(testResult)
                                    .font(.system(size: 10))
                                    .foregroundStyle(testResult.hasPrefix("OK") ? Theme.mint : .red)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }

                        Divider().opacity(0.5)

                        Text("Build the engine from the repository with:")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Text("dotnet build src/DiscImageStudio.Cli/DiscImageStudio.Cli.csproj -c Release")
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                        Text("The app also finds a bundled `Contents/Resources/cli/disc-image-studio`, the developer build under `src/DiscImageStudio.Cli/bin`, a Homebrew install, or a path on `PATH`.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(18)
        }
    }

    private var defaultsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Projects", subtitle: "Default location for new projects", icon: "folder")
                        HStack(spacing: 8) {
                            TextField("Projects folder", text: $settings.defaultProjectsDirectory)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 10.5, design: .monospaced))
                            Button("Choose…") { chooseProjectsFolder() }
                                .buttonStyle(SecondaryActionButtonStyle())
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Preview", subtitle: "Default projection size", icon: "eye")
                        Picker("Preview size", selection: $settings.previewSize) {
                            Text("512 px").tag(512)
                            Text("1024 px").tag(1024)
                            Text("1600 px").tag(1600)
                            Text("2048 px").tag(2048)
                            Text("4096 px").tag(4096)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "Native renderer", subtitle: "What runs in Swift", icon: "swift")
                        Text("The layer compositor, disc mask, tone preview, project documents and all UI are native Swift/SwiftUI. The physical CD/DVD/BD encoders remain the mature .NET engine from DiscImageStudio.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(18)
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "opticaldiscdrive.fill")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Disc Image Studio for macOS")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("Version 1.0.0 · Native SwiftUI frontend")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Text("A native macOS workspace for DiscImageStudio. Design, preview and export CD, DVD and single-layer BD-R visible-image discs using the upstream physical engine.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 10) {
                Link("Upstream project", destination: URL(string: "https://github.com/JiaFeiMiao-K-Cat/DiscImageStudio")!)
                Text("·")
                    .foregroundStyle(.tertiary)
                Link("License (GPL-3.0-or-later)", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
            }
            .font(.system(size: 11))
            Text("Disc burning is not exposed in the native frontend; generate an image and use your preferred macOS burning tool.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func chooseCLI() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose the disc-image-studio executable"
        if panel.runModal() == .OK, let url = panel.url {
            settings.cliPath = url.path
            model.refreshCLIDetection()
        }
    }

    private func chooseProjectsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose the default projects folder"
        if panel.runModal() == .OK, let url = panel.url {
            settings.defaultProjectsDirectory = url.path
        }
    }

    private func testEngine() {
        isTesting = true
        testResult = nil
        Task {
            defer { isTesting = false }
            guard let invocation = CLIService.shared.locateCLI(customPath: settings.cliPath) else {
                testResult = "Not found. Build the CLI or choose its path."
                return
            }
            do {
                let result = try await CLIService.shared.run(invocation, arguments: ["--help"])
                let firstLine = result.standardOutput.split(separator: "\n").first.map(String.init)
                testResult = "OK · " + (firstLine ?? "engine responded")
            } catch {
                testResult = "Failed · \(error.localizedDescription)"
            }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent, Theme.accentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "opticaldiscdrive.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 96, height: 96)
            .shadow(color: Theme.accent.opacity(0.4), radius: 18, y: 8)

            VStack(spacing: 4) {
                Text("Disc Image Studio")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Native SwiftUI frontend · 1.0.0")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text("This is an independent macOS frontend for the GPL-licensed DiscImageStudio project by JiaFeiMiao-K-Cat. The physical disc encoders remain the upstream .NET implementation; the interface, compositor and project editor are written in Swift.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Tag(text: "SwiftUI", color: Theme.accent)
                Tag(text: ".NET engine", color: Theme.mint)
                Tag(text: "GPL-3.0-or-later", color: Theme.amber)
            }

            HStack(spacing: 12) {
                Link("GitHub", destination: URL(string: "https://github.com/JiaFeiMiao-K-Cat/DiscImageStudio")!)
                Link("License", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
            }
            .font(.system(size: 11.5))

            Button("Close") { dismiss() }
                .buttonStyle(PrimaryActionButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 540, height: 480)
        .background(Theme.pageBackground)
    }
}
