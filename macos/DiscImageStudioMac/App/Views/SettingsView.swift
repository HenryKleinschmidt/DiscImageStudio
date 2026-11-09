import AppKit
import DiscImageStudioKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: WorkspaceViewModel
    @ObservedObject private var settings: AppSettings
    @ViewState private var isTesting = false
    @ViewState private var testResult: String?

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
        Form {
            Section("Disc Engine") {
                LabeledContent("Detected engine") {
                    Text(model.cliDetection)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent("CLI path") {
                    HStack {
                        TextField("Automatic", text: $settings.cliPath)
                            .accessibilityLabel("Custom CLI path")
                        Button("Choose…") { chooseCLI() }
                    }
                }
                HStack {
                    Button(isTesting ? "Testing…" : "Test Engine") { testEngine() }
                        .disabled(isTesting)
                    Button("Auto-detect") {
                        settings.resetCLIPath()
                        model.refreshCLIDetection()
                        testResult = nil
                    }
                    if isTesting { ProgressView().controlSize(.small) }
                }
                if let testResult {
                    Text(testResult).textSelection(.enabled)
                }
            }
            Section("Engine Setup") {
                Text("Choose an executable or a .NET CLI assembly, or let the app locate a bundled engine, developer build, Homebrew install or executable on PATH.")
                    .foregroundStyle(.secondary)
                Text("dotnet build src/DiscImageStudio.Cli/DiscImageStudio.Cli.csproj -c Release")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.cliPath) { _, _ in
            model.refreshCLIDetection()
            testResult = nil
        }
    }

    private var defaultsTab: some View {
        Form {
            Section("Projects") {
                LabeledContent("Default folder") {
                    HStack {
                        TextField("Projects folder", text: $settings.defaultProjectsDirectory)
                        Button("Choose…") { chooseProjectsFolder() }
                    }
                }
            }
            Section("Preview") {
                Picker("Default size", selection: $settings.previewSize) {
                    ForEach([512, 1024, 1600, 2048, 4096], id: \.self) { size in
                        Text("\(size) px").tag(size)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "opticaldiscdrive.fill")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Disc Image Studio for macOS")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("Version 1.0.0 · Native SwiftUI frontend")
                .font(.callout)
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
            .font(.caption)
            Text("Use the Burn workspace to write generated images with a compatible optical drive.")
                .font(.caption)
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
            Image(systemName: "opticaldiscdrive.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

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
            .font(.callout)

            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 540, height: 480)
        .background(Theme.pageBackground)
    }
}
