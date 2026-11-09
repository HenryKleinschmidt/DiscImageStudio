import DiscImageStudioKit
import SwiftUI

struct ProjectSettingsView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var geometry: ProjectGeometry
    @State private var presetID: String
    @State private var invertMapping: Bool
    @State private var usableText: String
    @State private var errorMessage: String?

    init(model: WorkspaceViewModel) {
        self.model = model
        let state = model.state
        let geometry = state?.geometry ?? model.family.defaultGeometry
        _name = State(initialValue: state?.name ?? "")
        _geometry = State(initialValue: geometry)
        _presetID = State(
            initialValue: PresetCatalog.matching(geometry, family: state?.family ?? .cd)?.id ?? ""
        )
        _invertMapping = State(initialValue: state?.invertMapping ?? false)
        _usableText = State(initialValue: geometry.usableSectors.map(String.init) ?? "")
    }

    private var family: DiscFamily { model.family }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 14) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(title: "Project", subtitle: "Name and medium", icon: "square.and.pencil")
                            TextField("Project name", text: $name)
                                .textFieldStyle(.roundedBorder)
                            HStack {
                                Text("Medium")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                FamilyBadge(family: family)
                                Text("fixed for this project")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(title: "Capture preset", subtitle: "Applies geometry only", icon: "opticaldisc")
                            Picker("", selection: $presetID) {
                                Text("Custom geometry").tag("")
                                ForEach(PresetCatalog.presets(for: family)) { preset in
                                    Text(preset.name).tag(preset.id)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: presetID) { _, newID in
                                guard let preset = PresetCatalog.preset(id: newID), preset.family == family else { return }
                                geometry = preset.geometry
                                invertMapping = preset.invertMapping
                                usableText = preset.geometry.usableSectors.map(String.init) ?? ""
                            }
                            if let preset = PresetCatalog.preset(id: presetID), preset.family == family {
                                Text(preset.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(title: "Generation geometry", subtitle: "Shared by design, preview and export", icon: "ruler")
                            HStack(spacing: 12) {
                                labeledField("Inner radius (mm)", value: $geometry.innerRadiusMm)
                                labeledField("Outer radius (mm)", value: $geometry.outerRadiusMm)
                            }
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    fieldLabel("Total sectors")
                                    TextField("", value: $geometry.sectors, format: .number.grouping(.never))
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: geometry.sectors) { _, _ in presetID = "" }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    fieldLabel("Usable sectors")
                                    TextField("Full geometry", text: $usableText)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: usableText) { _, newValue in
                                            geometry.usableSectors = Int64(newValue.trimmingCharacters(in: .whitespaces))
                                            presetID = ""
                                        }
                                }
                            }
                            HStack(spacing: 12) {
                                labeledField("Pitch linear", value: $geometry.pitchLinear)
                                labeledField("Pitch quadratic", value: $geometry.pitchQuadratic)
                            }
                            labeledField("Pitch cubic", value: $geometry.pitchCubic)
                            if family == .bd {
                                Toggle("Invert 3T/6T mapping", isOn: $invertMapping)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                if let projectURL = model.projectURL {
                    Text(projectURL.path)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save changes") { save() }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
        }
        .frame(width: 660, height: 700)
        .background(Theme.pageBackground)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent.opacity(0.14))
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Project settings")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Geometry is validated against the engine's \(family.label) constraints.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private func labeledField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(title)
            TextField("", value: value, format: .number.precision(.fractionLength(0...7)))
                .textFieldStyle(.roundedBorder)
                .onChange(of: value.wrappedValue) { _, _ in
                    if !presetID.isEmpty { presetID = "" }
                }
        }
    }

    private func save() {
        errorMessage = nil
        do {
            var finalGeometry = geometry
            let trimmed = usableText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                finalGeometry.usableSectors = nil
            } else if let usable = Int64(trimmed) {
                finalGeometry.usableSectors = usable
            } else {
                throw ProjectValidationError.invalidGeometry("Usable sectors must be an integer.")
            }
            try model.applyProjectSettings(
                name: name,
                geometry: finalGeometry,
                invertMapping: invertMapping
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
