import DiscImageStudioKit
import SwiftUI

struct CalibrationCanvas: View {
    let image: CGImage
    var outerPoints: [CGPoint] = []
    var holePoints: [CGPoint] = []
    var tracePoints: [CGPoint] = []
    var boundarySegments: [[CGPoint]] = []
    var showMeasurements = false
    var onAdd: (CGPoint) -> Void

    @State private var zoom: CGFloat = 1

    private var segmentColors: [Color] {
        [Theme.accent, Theme.mint, Theme.amber, Color(red: 0.9, green: 0.45, blue: 0.75), Color(red: 0.6, green: 0.55, blue: 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Click to place a point")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Zoom")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Picker("", selection: $zoom) {
                    Text("Fit").tag(CGFloat(1))
                    Text("2×").tag(CGFloat(2))
                    Text("4×").tag(CGFloat(4))
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            GeometryReader { geo in
                let fitScale = min(
                    (geo.size.width - 16) / CGFloat(image.width),
                    (geo.size.height - 16) / CGFloat(image.height)
                )
                let scale = max(0.01, fitScale * zoom)
                let contentWidth = CGFloat(image.width) * scale
                let contentHeight = CGFloat(image.height) * scale
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: contentWidth, height: contentHeight)
                        Canvas { context, _ in
                            let centre = CGPoint(
                                x: contentWidth / 2,
                                y: contentHeight / 2
                            )
                            var cross = Path()
                            cross.move(to: CGPoint(x: centre.x - 8, y: centre.y))
                            cross.addLine(to: CGPoint(x: centre.x + 8, y: centre.y))
                            cross.move(to: CGPoint(x: centre.x, y: centre.y - 8))
                            cross.addLine(to: CGPoint(x: centre.x, y: centre.y + 8))
                            context.stroke(cross, with: .color(.white.opacity(0.5)), lineWidth: 1)

                            for (index, point) in outerPoints.enumerated() {
                                drawPoint(context, point: point, scale: scale, color: .cyan, label: "\(index + 1)")
                            }
                            for (index, point) in holePoints.enumerated() {
                                drawPoint(context, point: point, scale: scale, color: .orange, label: "\(index + 1)")
                            }

                            if showMeasurements {
                                if tracePoints.count > 1 {
                                    var path = Path()
                                    path.move(to: scaled(tracePoints[0], scale))
                                    for point in tracePoints.dropFirst() {
                                        path.addLine(to: scaled(point, scale))
                                    }
                                    context.stroke(path, with: .color(Theme.mint), lineWidth: 1.5)
                                }
                                for point in tracePoints {
                                    drawPoint(context, point: point, scale: scale, color: Theme.mint)
                                }
                                for (index, segment) in boundarySegments.enumerated() {
                                    let color = segmentColors[index % segmentColors.count]
                                    if segment.count > 1 {
                                        var path = Path()
                                        path.move(to: scaled(segment[0], scale))
                                        for point in segment.dropFirst() {
                                            path.addLine(to: scaled(point, scale))
                                        }
                                        context.stroke(path, with: .color(color), lineWidth: 1.5)
                                    }
                                    for point in segment {
                                        drawPoint(context, point: point, scale: scale, color: color)
                                    }
                                }
                            }
                        }
                        .frame(width: contentWidth, height: contentHeight)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    onAdd(CGPoint(
                                        x: value.location.x / scale,
                                        y: value.location.y / scale
                                    ))
                                }
                        )
                    }
                    .frame(width: max(contentWidth, geo.size.width), height: max(contentHeight, geo.size.height))
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
    }

    private func scaled(_ point: CGPoint, _ scale: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }

    private func drawPoint(
        _ context: GraphicsContext,
        point: CGPoint,
        scale: CGFloat,
        color: Color,
        label: String? = nil
    ) {
        let location = scaled(point, scale)
        let circle = Path(ellipseIn: CGRect(x: location.x - 4.5, y: location.y - 4.5, width: 9, height: 9))
        context.fill(circle, with: .color(color.opacity(0.9)))
        context.stroke(circle, with: .color(.black.opacity(0.7)), lineWidth: 1)
        if let label {
            context.draw(
                Text(label)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.black),
                at: CGPoint(x: location.x + 7, y: location.y - 7)
            )
        }
    }
}
