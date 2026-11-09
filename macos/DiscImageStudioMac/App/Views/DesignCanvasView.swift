import DiscImageStudioKit
import SwiftUI

struct DesignCanvasView: View {
    @ObservedObject var model: WorkspaceViewModel
    @State private var dragOrigin: CGPoint?
    @State private var scaleOrigin: Double?
    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionTitle(
                    title: "Disc canvas",
                    subtitle: "120 mm disc · drag the selected layer",
                    icon: "circle.circle"
                )
                Spacer()
                if let state = model.state {
                    Tag(text: "\(String(format: "%.2f", state.contentOuterRadiusMm)) mm outer", color: Theme.mint)
                    Tag(text: "\(state.geometry.sectors.formatted(.number.grouping(.automatic))) sectors", color: .secondary)
                }
            }
            .padding(14)

            GeometryReader { geo in
                let side = max(180, min(geo.size.width, geo.size.height) - 34)
                let pixelsPerMm = side / 120.0
                if let state = model.state {
                    let contentDiameter = state.contentOuterRadiusMm * 2 * pixelsPerMm
                    let hubDiameter = 30.0 * pixelsPerMm
                    let holeDiameter = 15.0 * pixelsPerMm

                    ZStack {
                        DiscBackdrop()
                            .frame(width: side, height: side)
                            .shadow(color: .black.opacity(0.25), radius: 22, y: 12)

                        if let composite = model.designComposite {
                            Image(decorative: composite, scale: 1)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: contentDiameter, height: contentDiameter)
                                .clipShape(Circle())
                                .opacity(0.98)
                        } else if state.layers.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundStyle(.white.opacity(0.7))
                                Text("Drop an image to begin")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                                Button("Import images") { model.chooseImages() }
                                    .buttonStyle(SecondaryActionButtonStyle())
                            }
                        }

                        if !state.outputs.dataDirectory.isEmpty {
                            Circle()
                                .stroke(
                                    Theme.accent.opacity(0.65),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                                )
                                .frame(width: contentDiameter, height: contentDiameter)
                        }

                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color(white: 0.14), Color(white: 0.28), Color(white: 0.11)],
                                    center: .center,
                                    startRadius: 1,
                                    endRadius: hubDiameter / 2
                                )
                            )
                            .frame(width: hubDiameter, height: hubDiameter)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8))
                        Circle()
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .frame(width: holeDiameter, height: holeDiameter)
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 2))

                        Circle()
                            .strokeBorder(Color.white.opacity(0.20), lineWidth: 1.2)
                            .frame(width: side, height: side)

                        if let layer = model.selectedLayer,
                           let aspect = model.selectedLayerAspectRatio {
                            selectionOverlay(layer: layer, aspect: aspect, pixelsPerMm: pixelsPerMm, contentOuter: state.contentOuterRadiusMm)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(pixelsPerMm: pixelsPerMm))
                    .simultaneousGesture(scaleGesture())
                    .overlay(alignment: .bottomLeading) {
                        if isDropTarget {
                            Text("Drop images to import")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.accent, in: Capsule())
                                .foregroundStyle(.white)
                                .padding(12)
                        }
                    }
                    .overlay {
                        if isDropTarget {
                            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                .padding(4)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor).opacity(0.58),
                            Color(nsColor: .windowBackgroundColor).opacity(0.82)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .dropDestination(for: URL.self) { urls, _ in
            model.importImages(from: urls)
            return true
        } isTargeted: { isDropTarget = $0 }
    }

    @ViewBuilder
    private func selectionOverlay(
        layer: ProjectLayer,
        aspect: Double,
        pixelsPerMm: Double,
        contentOuter: Double
    ) -> some View {
        let diameter = contentOuter * 2
        let baseWidth = aspect >= 1 ? diameter : diameter * aspect
        let baseHeight = aspect >= 1 ? diameter / aspect : diameter
        let width = baseWidth * layer.scale * pixelsPerMm
        let height = baseHeight * layer.scale * pixelsPerMm
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .stroke(Theme.mint, style: StrokeStyle(lineWidth: 1.4, dash: [5, 3]))
            .frame(width: width, height: height)
            .rotationEffect(.degrees(layer.rotationDeg))
            .offset(x: layer.translateXMm * pixelsPerMm, y: layer.translateYMm * pixelsPerMm)
            .overlay(alignment: .topLeading) {
                Text(layer.name)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.mint, in: Capsule())
                    .foregroundStyle(.black.opacity(0.8))
                    .offset(y: -16)
                    .lineLimit(1)
            }
            .allowsHitTesting(false)
    }

    private func dragGesture(pixelsPerMm: Double) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard let layer = model.selectedLayer else { return }
                if dragOrigin == nil {
                    dragOrigin = CGPoint(x: layer.translateXMm, y: layer.translateYMm)
                }
                guard let origin = dragOrigin else { return }
                let x = min(max(origin.x + value.translation.width / pixelsPerMm, -60), 60)
                let y = min(max(origin.y + value.translation.height / pixelsPerMm, -60), 60)
                model.updateLayer(layer.id) {
                    $0.translateXMm = x
                    $0.translateYMm = y
                }
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private func scaleGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard let layer = model.selectedLayer else { return }
                if scaleOrigin == nil { scaleOrigin = layer.scale }
                guard let origin = scaleOrigin else { return }
                let scale = min(max(origin * value, 0.05), 4.0)
                model.updateLayer(layer.id) { $0.scale = scale }
            }
            .onEnded { _ in scaleOrigin = nil }
    }
}
