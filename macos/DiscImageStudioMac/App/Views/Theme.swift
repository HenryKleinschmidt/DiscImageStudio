import DiscImageStudioKit
import SwiftUI

// Select the property wrapper explicitly: newer SDKs also export a State macro.
// The wrapper retains the macOS 14 storage and Binding behavior in Swift 5 mode.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Theme {
    static let accent = Color.accentColor
    static let mint = Color.green
    static let amber = Color.orange
    static let panelRadius: CGFloat = 12
    static let layerPanelWidth: CGFloat = 252

    static let pageBackground = Color(nsColor: .windowBackgroundColor)
}

/// Native grouping keeps controls legible in both appearances and follows system contrast.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        GroupBox {
            content()
                .padding(max(0, padding - 8))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?
    var icon: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct FamilyBadge: View {
    let family: DiscFamily
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: family.systemImage)
                .font(.caption)
            Text(family.shortLabel)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(Theme.accent)
    }
}

struct Tag: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.7))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

struct LabeledValue: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: monospaced ? .monospaced : .default))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct DiscThumbnail: View {
    let base64: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let base64,
               let data = Data(base64Encoded: base64),
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(
                        AngularGradient(
                            colors: [
                                Color(white: 0.32), Color(white: 0.56),
                                Color(white: 0.22), Color(white: 0.62),
                                Color(white: 0.32)
                            ],
                            center: .center
                        )
                    )
                    Circle()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    Circle()
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .frame(width: size * 0.22, height: size * 0.22)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}

struct DiscBackdrop: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.20),
                            Color(white: 0.36),
                            Color(white: 0.16)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 320
                    )
                )
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Color(red: 0.55, green: 0.65, blue: 0.9).opacity(0.6),
                            Color(red: 0.9, green: 0.7, blue: 0.55).opacity(0.5),
                            Color(red: 0.55, green: 0.9, blue: 0.75).opacity(0.5),
                            Color(red: 0.55, green: 0.65, blue: 0.9).opacity(0.6)
                        ],
                        center: .center
                    ),
                    lineWidth: 2
                )
                .padding(1)
            Circle()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                .padding(14)
        }
    }
}
