import DiscImageStudioKit
import SwiftUI

struct DesignInspector: View {
    @ObservedObject var model: WorkspaceViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let layer = model.selectedLayer {
                    layerCard(layer)
                } else {
                    Card {
                        VStack(spacing: 10) {
                            Image(systemName: "cursorarrow.click.2")
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(Theme.accent.opacity(0.8))
                            Text("Select a layer")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Choose a row on the left to edit its position, rotation and scale.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }

                toneCard
                filesCard
                geometryCard
            }
            .padding(12)
        }
    }

    private func layerCard(_ layer: ProjectLayer) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: "Layer", subtitle: layer.name, icon: "square.3.layers.3d")
                    Spacer()
                    Button {
                        model.removeSelectedLayer()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Remove selected layer")
                    .help("Remove selected layer")
                }

                TextField("Layer name", text: model.layerBinding(layer.id, \.name, fallback: layer.name))
                    .textFieldStyle(.roundedBorder)

                SliderRow(
                    title: "Horizontal",
                    range: -60...60,
                    value: model.layerBinding(layer.id, \.translateXMm, fallback: 0),
                    display: { String(format: "%+.1f mm", $0) }
                )
                SliderRow(
                    title: "Vertical",
                    range: -60...60,
                    value: model.layerBinding(layer.id, \.translateYMm, fallback: 0),
                    display: { String(format: "%+.1f mm", $0) }
                )
                SliderRow(
                    title: "Rotation",
                    range: -180...180,
                    value: model.layerBinding(layer.id, \.rotationDeg, fallback: 0),
                    display: { String(format: "%.0f°", $0) }
                )
                SliderRow(
                    title: "Scale",
                    range: 0.05...4,
                    value: model.layerBinding(layer.id, \.scale, fallback: 1),
                    display: { String(format: "%.0f%%", $0 * 100) }
                )

                HStack(spacing: 8) {
                    Button("Center") {
                        model.updateLayer(layer.id) {
                            $0.translateXMm = 0
                            $0.translateYMm = 0
                        }
                    }
                    .buttonStyle(.bordered)
                    Button("Reset transform") {
                        model.updateLayer(layer.id) {
                            $0.translateXMm = 0
                            $0.translateYMm = 0
                            $0.rotationDeg = 0
                            $0.scale = 1
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var toneCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: "Tone", subtitle: "How grey becomes burn", icon: "circle.lefthalf.filled")
                    Spacer()
                    if model.tonePreview != nil {
                        Tag(text: "LIVE", color: Theme.mint)
                    }
                }

                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color(white: 0.19), Color(white: 0.29), Color(white: 0.15)],
                                    center: .center,
                                    startRadius: 2,
                                    endRadius: 100
                                )
                            )
                        if let image = model.tonePreview {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "circle.dashed")
                                .font(.system(size: 30, weight: .light))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .frame(width: 196, height: 196)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    Spacer()
                }

                SliderRow(
                    title: "Dither",
                    range: 0...1,
                    value: model.projectBinding(\.tone.ditherStrength, fallback: 0.75),
                    display: { String(format: "%.0f%%", $0 * 100) }
                )

                HStack {
                    Text("Palette")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.family == .cd {
                        Picker("Tone palette", selection: model.projectBinding(\.tone.levels, fallback: 2)) {
                            Text("2 levels").tag(2)
                            Text("4 levels").tag(4)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    } else {
                        Text("2 levels (fixed)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                SliderRow(
                    title: "Brightness",
                    range: -64...64,
                    value: model.projectBinding(\.tone.brightness, fallback: 0),
                    display: { String(format: "%+.0f", $0) }
                )

                Toggle(
                    "sRGB linearization",
                    isOn: model.projectBinding(\.tone.srgbLinearization, fallback: false)
                )
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.caption)

                if model.family == .bd {
                    Toggle(
                        "Invert 3T/6T mapping",
                        isOn: model.projectBinding(\.invertMapping, fallback: false)
                    )
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.caption)
                }

                HStack {
                    Text(model.state?.tone.summary ?? "")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer()
                    Button("Reset") {
                        model.apply { $0.tone = .photo }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var filesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Disc files", subtitle: "Optional hybrid content", icon: "folder.badge.plus")

                HStack(spacing: 6) {
                    TextField(
                        "No folder",
                        text: model.projectBinding(\.outputs.dataDirectory, fallback: "")
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    Button {
                        if let path = model.chooseDataDirectory() {
                            model.apply { $0.outputs.dataDirectory = path }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.plain)
                }

                if !(model.state?.outputs.dataDirectory.isEmpty ?? true) {
                    TextField(
                        "Volume label",
                        text: model.projectBinding(\.outputs.volumeLabel, fallback: "DISC_IMAGE")
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))

                    Picker(
                        "File placement",
                        selection: model.projectBinding(\.outputs.filesAtOuterRing, fallback: false)
                    ) {
                        Text("Inner ring").tag(false)
                        Text("Outer ring").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .font(.caption)

                    Text("Files are copied by the engine at generation time; the design never includes them.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var geometryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                SectionTitle(title: "Geometry", subtitle: "Owned by project settings", icon: "ruler")
                if let state = model.state {
                    HStack(spacing: 12) {
                        LabeledValue(label: "Inner", value: String(format: "%.3f mm", state.geometry.innerRadiusMm))
                        LabeledValue(label: "Outer", value: String(format: "%.3f mm", state.geometry.outerRadiusMm))
                    }
                    HStack(spacing: 12) {
                        LabeledValue(label: "Sectors", value: state.geometry.sectors.formatted())
                        LabeledValue(
                            label: "Usable",
                            value: state.geometry.usableSectors?.formatted() ?? "Full"
                        )
                    }
                    Button {
                        model.isProjectSettingsPresented = true
                    } label: {
                        Label("Edit geometry & preset", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

struct SliderRow: View {
    let title: String
    let range: ClosedRange<Double>
    @Binding var value: Double
    let display: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(display(value))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            Slider(value: $value, in: range) { Text(title) }
                .labelsHidden()
                .accessibilityValue(display(value))
                .controlSize(.small)
        }
    }
}
