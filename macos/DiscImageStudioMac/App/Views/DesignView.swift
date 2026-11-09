import AppKit
import DiscImageStudioKit
import SwiftUI

struct DesignView: View {
    @ObservedObject var model: WorkspaceViewModel

    var body: some View {
        HSplitView {
            LayerPanel(model: model)
                .frame(minWidth: 220, idealWidth: Theme.layerPanelWidth, maxWidth: 340)
            DesignCanvasView(model: model)
                .frame(minWidth: 420, maxWidth: .infinity, minHeight: 420)
        }
        .inspector(isPresented: $model.isInspectorPresented) {
            DesignInspector(model: model)
                .inspectorColumnWidth(min: 280, ideal: 312, max: 390)
        }
    }
}

// MARK: - Layer panel

struct LayerPanel: View {
    @ObservedObject var model: WorkspaceViewModel
    @ViewState private var isDropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SectionTitle(title: "Layers", subtitle: "Topmost first", icon: "square.3.layers.3d")
                Spacer()
                Button {
                    model.chooseImages()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .padding(6)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.accent)
                .help("Import images")
                .accessibilityLabel("Import images")
            }
            .padding(14)

            Divider().opacity(0.5)

            if model.state?.layers.isEmpty ?? true {
                VStack(spacing: 12) {
                    Image(systemName: isDropTarget ? "arrow.down.doc.fill" : "photo.on.rectangle.angled")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(isDropTarget ? Theme.accent : .secondary)
                    Text("Drop images here")
                        .font(.system(size: 12, weight: .medium))
                    Text("PNG, JPEG, BMP, GIF, TIFF or HEIC")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Import…") { model.chooseImages() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isDropTarget ? Theme.accent : Color.primary.opacity(0.10),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                        .padding(12)
                )
            } else {
                List(selection: $model.selectedLayerID) {
                    ForEach(model.state?.layers ?? []) { layer in
                        layerRow(layer).tag(layer.id)
                    }
                    .onMove(perform: model.moveLayers)
                }
                .listStyle(.inset)
            }

            Divider().opacity(0.5)

            HStack(spacing: 7) {
                Button {
                    model.chooseImages()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    model.removeSelectedLayer()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(model.selectedLayerID == nil)

                Spacer()

                Button {
                    moveSelected(up: true)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .frame(minWidth: 24, minHeight: 24)
                .disabled(!canMoveUp)
                .accessibilityLabel("Move layer up")
                .help("Move selected layer up")

                Button {
                    moveSelected(up: false)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .frame(minWidth: 24, minHeight: 24)
                .disabled(!canMoveDown)
                .accessibilityLabel("Move layer down")
                .help("Move selected layer down")
            }
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            if isDropTarget { Rectangle().strokeBorder(Theme.accent, lineWidth: 2) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.importImages(from: urls)
            return true
        } isTargeted: { isDropTarget = $0 }
    }

    private func layerRow(_ layer: ProjectLayer) -> some View {
        let selected = model.selectedLayerID == layer.id
        return HStack(spacing: 9) {
            LocalThumbnail(path: layer.imagePath)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .opacity(layer.visible ? 1 : 0.35)

            VStack(alignment: .leading, spacing: 1) {
                Text(layer.name)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Text(String(format: "%.0f%% · %.1f, %.1f mm", layer.scale * 100, layer.translateXMm, layer.translateYMm))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            Button {
                model.toggleVisibility(layer.id)
            } label: {
                Image(systemName: layer.visible ? "eye" : "eye.slash")
                    .font(.caption)
                    .foregroundStyle(layer.visible ? .secondary : .tertiary)
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 24, minHeight: 24)
            .help(layer.visible ? "Hide layer" : "Show layer")
            .accessibilityLabel("\(layer.visible ? "Hide" : "Show") \(layer.name)")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button(layer.visible ? "Hide" : "Show") { model.toggleVisibility(layer.id) }
            Button("Move to Top") { model.moveLayer(layer.id, before: nil) }
            Divider()
            Button("Remove", role: .destructive) {
                model.selectedLayerID = layer.id
                model.removeSelectedLayer()
            }
        }
    }

    private var canMoveUp: Bool {
        guard let id = model.selectedLayerID,
              let layers = model.state?.layers,
              let index = layers.firstIndex(where: { $0.id == id })
        else { return false }
        return index > 0
    }

    private var canMoveDown: Bool {
        guard let id = model.selectedLayerID,
              let layers = model.state?.layers,
              let index = layers.firstIndex(where: { $0.id == id })
        else { return false }
        return index < layers.count - 1
    }

    private func moveSelected(up: Bool) {
        guard let id = model.selectedLayerID,
              let layers = model.state?.layers,
              let index = layers.firstIndex(where: { $0.id == id })
        else { return }
        if up, index > 0 {
            model.moveLayers(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
        } else if !up, index < layers.count - 1 {
            model.moveLayers(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
        }
    }
}

struct LocalThumbnail: View {
    let path: String
    @ViewState private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                Image(systemName: "photo")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: path) {
            image = NSImage(contentsOfFile: path)
        }
    }
}
