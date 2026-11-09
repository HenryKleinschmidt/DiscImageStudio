import DiscImageStudioKit
import SwiftUI

struct PreviewView: View {
    @ObservedObject var model: WorkspaceViewModel

    private let sizes = [512, 1024, 1600, 2048, 4096]

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 12) {
                controls
                previewStage
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .padding(12)
        .inspector(isPresented: $model.isInspectorPresented) {
            sidePanel.padding()
                .inspectorColumnWidth(min: 260, ideal: 280, max: 360)
        }
        .task {
            model.renderPreviewIfNeeded()
        }
    }

    private var controls: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 14) {
                    Picker("Preview source", selection: $model.previewMode) {
                        ForEach(PreviewMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
                    .onChange(of: model.previewMode) { _, _ in
                        model.renderPreview()
                    }

                    Divider().frame(height: 22)

                    HStack(spacing: 6) {
                        Text("Size")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Picker("Preview size", selection: $model.previewSize) {
                            ForEach(sizes, id: \.self) { size in
                                Text("\(size) px").tag(size)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 105)
                        .onChange(of: model.previewSize) { _, _ in
                            model.notePreviewSizeChanged()
                            model.renderPreview()
                        }
                    }

                    Spacer()

                    if model.isPreviewing {
                        ProgressView().controlSize(.small)
                    }

                    Button {
                        model.renderPreview()
                    } label: {
                        Label("Render", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled((model.state?.layers.isEmpty ?? true) || model.isPreviewing)
                }

                HStack(spacing: 7) {
                    Text("Measured radii")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    TextField(
                        "Inner radius (mm)",
                        value: $model.previewMeasuredInnerRadiusMm,
                        format: .number.precision(.fractionLength(0...3))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    Text("–")
                        .foregroundStyle(.tertiary)
                    TextField(
                        "Outer radius (mm)",
                        value: $model.previewMeasuredOuterRadiusMm,
                        format: .number.precision(.fractionLength(0...3))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    Text("mm")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("Used only by the inspection projection; generation uses the project geometry.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 6)
                    Spacer()
                }
            }
        }
    }

    private var previewStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.10), Color(white: 0.16), Color(white: 0.09)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            if let image = model.previewImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(20)
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            } else if model.isPreviewing {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(model.previewStatus)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(model.state?.layers.isEmpty ?? true ? "Import a design first" : "No preview yet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Text(model.previewStatus)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    if !(model.state?.layers.isEmpty ?? true) {
                        Button("Render preview") { model.renderPreview() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidePanel: some View {
        ScrollView {
            VStack(spacing: 12) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "Inspector", subtitle: model.previewMode.title, icon: "info.circle")
                        if let state = model.state {
                            HStack(spacing: 10) {
                                FamilyBadge(family: state.family)
                                Tag(text: "\(model.previewSize) px", color: Theme.mint)
                            }
                            Divider().opacity(0.5)
                            LabeledValue(label: "Geometry inner", value: String(format: "%.3f mm", state.geometry.innerRadiusMm))
                            LabeledValue(label: "Geometry outer", value: String(format: "%.3f mm", state.geometry.outerRadiusMm))
                            LabeledValue(
                                label: "Measured outer",
                                value: String(format: "%.3f mm", model.previewMeasuredOuterRadiusMm)
                            )
                            LabeledValue(
                                label: "Sectors",
                                value: state.geometry.sectors.formatted()
                            )
                            LabeledValue(
                                label: "Tone",
                                value: state.tone.summary
                            )
                        }
                        Divider().opacity(0.5)
                        Text(model.previewStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if model.family == .bd {
                    Card {
                        VStack(alignment: .leading, spacing: 7) {
                            Label("Native BD-R projection", systemImage: "opticaldiscdrive")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                            Text("The C# CLI has no standalone BD preview command, so BD uses the same native tone mapping the design canvas uses. Export still runs the engine's full 17PP/ECC pipeline.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Preview source", systemImage: "photo")
                            .font(.system(size: 11, weight: .semibold))
                        Text(model.previewMode == .design
                             ? "Design projection samples the 4096 px composite through the engine's geometry."
                             : "Read-back renders the generated artifact itself. Generate an image first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 0)
        }
    }
}
