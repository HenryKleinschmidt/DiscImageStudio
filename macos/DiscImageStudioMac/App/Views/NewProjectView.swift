import AppKit
import DiscImageStudioKit
import SwiftUI

struct NewProjectView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var family: DiscFamily
    @State private var name = "Untitled Disc"
    @State private var presetID: String
    @State private var geometry: ProjectGeometry
    @State private var invertMapping: Bool
    @State private var projectDirectory: String
    @State private var outputPath: String
    @State private var usableText: String
    @State private var customOutput = false
    @State private var errorMessage: String?

    init(model: WorkspaceViewModel, initialFamily: DiscFamily) {
        self.model = model
        let preset = PresetCatalog.presets(for: initialFamily).first
        let geometry = preset?.geometry ?? initialFamily.defaultGeometry
        let directory = model.settings.defaultProjectsDirectory
        let output = URL(fileURLWithPath: directory)
            .appendingPathComponent("Untitled Disc")
            .appendingPathExtension(initialFamily.defaultOutputExtension)
        _family = State(initialValue: initialFamily)
        _presetID = State(initialValue: preset?.id ?? "")
        _geometry = State(initialValue: geometry)
        _invertMapping = State(initialValue: preset?.invertMapping ?? false)
        _projectDirectory = State(initialValue: directory)
        _outputPath = State(initialValue: output.path)
        _usableText = State(initialValue: geometry.usableSectors.map(String.init) ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    familyPicker
                    detailsCard
                    geometryCard
                    outputCard
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 2)
                    }
                }
                .padding(22)
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 720)
        .background(Theme.pageBackground)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent.opacity(0.14))
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("New disc project")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("The medium is fixed for the life of the project. Geometry can be changed later.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var familyPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionTitle(title: "Medium", subtitle: "Pick the physical disc family", icon: "opticaldisc")
            HStack(spacing: 10) {
                ForEach(DiscFamily.allCases) { candidate in
                    Button {
                        selectFamily(candidate)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: candidate.systemImage)
                                .font(.system(size: 16, weight: .medium))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(candidate.label)
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(candidate.tagline)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if family == candidate {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(family == candidate ? Theme.accent.opacity(0.10) : Color.primary.opacity(0.035))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(
                                    family == candidate ? Theme.accent.opacity(0.55) : Color.primary.opacity(0.07),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var detailsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                SectionTitle(title: "Project", subtitle: "Name and capture preset", icon: "square.and.pencil")
                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, _ in
                        if !customOutput {
                            outputPath = suggestedOutputURL().path
                        }
                    }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Disc preset")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $presetID) {
                            ForEach(PresetCatalog.presets(for: family)) { preset in
                                Text(preset.name).tag(preset.id)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: presetID) { _, newID in
                            if let preset = PresetCatalog.preset(id: newID), preset.family == family {
                                geometry = preset.geometry
                                invertMapping = preset.invertMapping
                                usableText = preset.geometry.usableSectors.map(String.init) ?? ""
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if family == .bd {
                        Toggle("Invert 3T/6T mapping", isOn: $invertMapping)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11.5))
                    }
                }

                if let preset = PresetCatalog.preset(id: presetID) {
                    Text(preset.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var geometryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                SectionTitle(
                    title: "Generation geometry",
                    subtitle: "Saved in the project and shared with the engine",
                    icon: "ruler"
                )
                HStack(spacing: 12) {
                    numberField("Inner radius", value: $geometry.innerRadiusMm, unit: "mm")
                    numberField("Outer radius", value: $geometry.outerRadiusMm, unit: "mm")
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Total sectors")
                        TextField("", value: $geometry.sectors, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Usable sectors")
                        TextField("Full geometry", text: $usableText)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: usableText) { _, _ in
                                geometry.usableSectors = Int64(usableText.trimmingCharacters(in: .whitespaces))
                            }
                    }
                }
                Text(family == .bd
                     ? "BD-R geometry must be 32-sector aligned and no larger than 12,219,392 sectors."
                     : "Usable sectors limit the written area; leave blank to write the full geometry.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var outputCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                SectionTitle(title: "Files", subtitle: "Where the project and generated artifact live", icon: "folder")
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Project folder")
                        TextField("", text: $projectDirectory)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button("Choose…") { chooseProjectDirectory() }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .padding(.top, 14)
                }
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Output file")
                        TextField("", text: $outputPath)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: outputPath) { _, _ in customOutput = true }
                    }
                    Button("Choose…") {
                        if let path = model.chooseOutputPath(family: family) {
                            outputPath = path
                        }
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .padding(.top, 14)
                }
                Text(projectURL.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let preset = PresetCatalog.preset(id: presetID) {
                Text(preset.name)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                create()
            } label: {
                Label("Create project", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private func numberField(_ title: String, value: Binding<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("\(title) (\(unit))")
            TextField("", value: value, format: .number.precision(.fractionLength(0...6)))
                .textFieldStyle(.roundedBorder)
        }
    }

    private var projectURL: URL {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled"
            : name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        return URL(fileURLWithPath: (projectDirectory as NSString).expandingTildeInPath)
            .appendingPathComponent(base)
            .appendingPathExtension("discproj")
    }

    private func suggestedOutputURL() -> URL {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled"
            : name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        return URL(fileURLWithPath: (projectDirectory as NSString).expandingTildeInPath)
            .appendingPathComponent(base)
            .appendingPathExtension(family.defaultOutputExtension)
    }

    private func selectFamily(_ newFamily: DiscFamily) {
        guard newFamily != family else { return }
        family = newFamily
        if let preset = PresetCatalog.presets(for: newFamily).first {
            presetID = preset.id
            geometry = preset.geometry
            invertMapping = preset.invertMapping
            usableText = preset.geometry.usableSectors.map(String.init) ?? ""
        } else {
            geometry = newFamily.defaultGeometry
            invertMapping = false
            usableText = geometry.usableSectors.map(String.init) ?? ""
        }
        if !customOutput {
            outputPath = suggestedOutputURL().path
        }
    }

    private func chooseProjectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose where to store the project"
        if panel.runModal() == .OK, let url = panel.url {
            projectDirectory = url.path
            if !customOutput {
                outputPath = suggestedOutputURL().path
            }
        }
    }

    private func create() {
        errorMessage = nil
        do {
            var finalGeometry = geometry
            let usableText = usableText.trimmingCharacters(in: .whitespacesAndNewlines)
            if usableText.isEmpty {
                finalGeometry.usableSectors = nil
            } else if let usable = Int64(usableText) {
                finalGeometry.usableSectors = usable
            } else {
                throw ProjectValidationError.invalidGeometry("Usable sectors must be an integer.")
            }
            try finalGeometry.validate(family: family)
            guard !outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProjectValidationError.invalidProject("Choose an output file.")
            }
            try AppPaths.ensureDirectory(
                URL(fileURLWithPath: (projectDirectory as NSString).expandingTildeInPath)
            )
            try model.createProject(
                name: name,
                family: family,
                geometry: finalGeometry,
                invertMapping: invertMapping,
                projectURL: projectURL,
                outputURL: URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
            )
            if model.hasProject {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
