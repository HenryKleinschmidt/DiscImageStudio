import DiscImageStudioKit
import SwiftUI

enum Theme {
    static let accent = Color(red: 0.30, green: 0.55, blue: 1.0)
    static let accentDeep = Color(red: 0.16, green: 0.32, blue: 0.85)
    static let mint = Color(red: 0.22, green: 0.78, blue: 0.68)
    static let amber = Color(red: 1.0, green: 0.68, blue: 0.24)
    static let cardRadius: CGFloat = 16
    static let panelRadius: CGFloat = 12
    static let pagePadding: CGFloat = 22
    static let sidebarWidth: CGFloat = 232
    static let inspectorWidth: CGFloat = 312
    static let layerPanelWidth: CGFloat = 252

    static let pageBackground = LinearGradient(
        colors: [
            Color(nsColor: .windowBackgroundColor),
            Color(nsColor: .underPageBackgroundColor).opacity(0.55)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
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
                        .font(.system(size: 11))
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
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            Text(family.shortLabel)
                .font(.system(size: compact ? 9 : 10, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 3 : 4)
        .background(Theme.accent.opacity(0.14), in: Capsule())
        .foregroundStyle(Theme.accent)
    }
}

struct Tag: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [tint, tint.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .shadow(color: tint.opacity(configuration.isPressed ? 0.1 : 0.28), radius: 8, y: 4)
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.42)
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
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
                    .buttonStyle(PrimaryActionButtonStyle())
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
                .font(.system(size: 10, weight: .medium))
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
