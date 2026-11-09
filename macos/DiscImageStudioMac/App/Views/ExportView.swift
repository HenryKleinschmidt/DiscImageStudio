import DiscImageStudioKit
import SwiftUI

struct ExportView: View {
    @ObservedObject var model: WorkspaceViewModel

    var body: some View {
        HStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 12) {
                    sourceCard
                    outputCard
                    optionsCard
                    if let state = model.state {
                        summaryCard(state)
                    }
                }
                .padding(.trailing, 2)
            }
            .frame(width: 430)

            logPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
    }

    private var sourceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Source", subtitle: "Export-quality native composite", icon: "photo.stack")
                if let state = model.state {
                    HStack(spacing: 10) {
                        FamilyBadge(family: state.family)
                        Tag(text: "\(state.layers.count) layers", color: Theme.mint)
                        Tag(text: "8192 px", color: .secondary)
                        Spacer()
                    }
                    Text(state.layers.isEmpty
                         ? "Import at least one image on the Design page."
                         : "Layers are flattened by the SwiftUI compositor, then quantized by the engine's tone profile.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var outputCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                SectionTitle(title: "Destination", subtitle: "Written by the .NET disc engine", icon: "externaldrive")
                HStack(spacing: 6) {
                    TextField(
                        "Output file",
                        text: model.projectBinding(\.outputs.outputPath, fallback: "")
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10.5, design: .monospaced))
                    Button {
                        if let path = model.chooseOutputPath(family: model.family) {
                            model.apply { $0.outputs.outputPath = path }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.plain)
                }
                Text(model.outputDisplayName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    TextField(
                        "Optional disc files folder",
                        text: model.projectBinding(\.outputs.dataDirectory, fallback: "")
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10.5, design: .monospaced))
                    Button {
                        if let path = model.chooseDataDirectory() {
                            model.apply { $0.outputs.dataDirectory = path }
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.plain)
                }

                if !(model.state?.outputs.dataDirectory.isEmpty ?? true) {
                    TextField(
                        "Volume label",
                        text: model.projectBinding(\.outputs.volumeLabel, fallback: "DISC_IMAGE")
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10.5, design: .monospaced))
                }
            }
        }
    }

    private var optionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Options", subtitle: familyHint, icon: "switch.2")

                if model.family == .cd {
                    Toggle("Write CUE sheet", isOn: model.projectBinding(\.outputs.writeCue, fallback: true))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Toggle("Delay interleave", isOn: model.projectBinding(\.outputs.interleave, fallback: true))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Text("Without disc files the engine writes a WAV (or RAW) audio track. With disc files it writes a Mode 1 ISO.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.family == .dvd {
                    Toggle(
                        "Experimental read compatibility",
                        isOn: model.projectBinding(\.outputs.dvdReadCompatibility, fallback: false)
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    Text("Read compatibility reserves drawing byte patterns for players that struggle with extreme high-frequency content.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.family == .bd {
                    Text("BD-R export includes the UDF 2.01 filesystem when a folder is selected. The engine writes the full single-layer ISO.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !(model.state?.outputs.dataDirectory.isEmpty ?? true) {
                    Picker(
                        "Disc files",
                        selection: model.projectBinding(\.outputs.filesAtOuterRing, fallback: false)
                    ) {
                        Text("Inner ring").tag(false)
                        Text("Outer ring").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private func summaryCard(_ state: ProjectState) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                SectionTitle(title: "Generation", subtitle: "What will be written", icon: "checklist")
                LabeledValue(label: "Medium", value: state.family.label)
                LabeledValue(label: "Tone", value: state.tone.summary)
                LabeledValue(
                    label: "Usable sectors",
                    value: state.geometry.usableSectors?.formatted() ?? "Full geometry"
                )
                Divider().opacity(0.5)
                HStack(spacing: 8) {
                    Button {
                        model.generateImage()
                    } label: {
                        Label(model.isExporting ? "Generating…" : "Generate image", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(!model.canExport || model.isExporting)

                    if model.isExporting {
                        Button("Cancel") { model.cancelExport() }
                            .buttonStyle(SecondaryActionButtonStyle())
                    }
                }
            }
        }
    }

    private var logPanel: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Engine log")
                            .font(.system(size: 12, weight: .semibold))
                        Text(model.exportStatus)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if model.isExporting {
                        ProgressView().controlSize(.small)
                    }
                    if let output = model.lastOutputURL {
                        Button {
                            model.revealOutput()
                        } label: {
                            Label("Reveal", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .help("Reveal \(output.lastPathComponent) in Finder")
                    }
                }
                .padding(14)

                Divider().opacity(0.5)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            if model.exportLog.isEmpty {
                                Text("The command line, engine progress and errors appear here.")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(14)
                            } else {
                                Text(model.exportLog)
                                    .font(.system(size: 10, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .id("log-end")
                            }
                        }
                    }
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
                    .onChange(of: model.exportLog) { _, _ in
                        withAnimation(.linear(duration: 0.12)) {
                            proxy.scrollTo("log-end", anchor: .bottom)
                        }
                    }
                }

                if let output = model.lastOutputURL {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.mint)
                        Text(output.path)
                            .font(.system(size: 9.5, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Show in Finder") { model.revealOutput() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.025))
                }
            }
        }
    }

    private var familyHint: String {
        switch model.family {
        case .cd: return "Audio/data delivery"
        case .dvd: return "ISO image delivery"
        case .bd: return "UDF 2.01 image delivery"
        }
    }
}
