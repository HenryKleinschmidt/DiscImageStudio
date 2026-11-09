import AppKit
import DiscImageStudioKit
import SwiftUI

struct HomeView: View {
    @ObservedObject var model: WorkspaceViewModel
    @State private var hoveredRecent: String?

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                hero
                familySection
                recentSection
                footer
            }
            .frame(maxWidth: 1120)
            .padding(.horizontal, 34)
            .padding(.top, 26)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.pageBackground)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent, Theme.accentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "opticaldiscdrive.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 1) {
                Text("Disc Image Studio")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Native SwiftUI frontend for macOS")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.presentOpenProjectPanel()
            } label: {
                Label("Open Project", systemImage: "folder")
            }
            .buttonStyle(SecondaryActionButtonStyle())

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .help("Settings")
        }
    }

    private var hero: some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 7) {
                    Circle().fill(Theme.mint).frame(width: 6, height: 6)
                    Text("DRAWING WITH LIGHT")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(Theme.mint)
                }
                Text("Turn a picture into a\nvisible optical disc.")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .lineSpacing(-2)
                Text("Compose artwork in millimetres, tune the burn pattern, and generate a CD, DVD or single-layer BD-R image with the same physical engine as the desktop app.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .frame(maxWidth: 500, alignment: .leading)
                HStack(spacing: 10) {
                    Button {
                        model.presentNewProject(family: .dvd)
                    } label: {
                        Label("Start a project", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())

                    Button {
                        model.presentOpenProjectPanel()
                    } label: {
                        Label("Browse projects", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 10)

            ZStack {
                DiscBackdrop()
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Theme.accent.opacity(0.85),
                                Theme.mint.opacity(0.75),
                                Color(red: 0.95, green: 0.55, blue: 0.35).opacity(0.8),
                                Theme.accentDeep.opacity(0.85),
                                Theme.accent.opacity(0.85)
                            ],
                            center: .center
                        )
                    )
                    .padding(62)
                    .blur(radius: 14)
                    .opacity(0.9)
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 54, height: 54)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 250, height: 250)
            .shadow(color: .black.opacity(0.25), radius: 34, y: 16)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor),
                            Theme.accentDeep.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var familySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Create a disc")
                    .font(.system(size: 16, weight: .semibold))
                Text("Pick the medium; the geometry comes from the engine's calibrated presets.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 14) {
                ForEach(DiscFamily.allCases) { family in
                    familyCard(family)
                }
            }
        }
    }

    private func familyCard(_ family: DiscFamily) -> some View {
        Button {
            model.presentNewProject(family: family)
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.accent.opacity(0.13))
                        Image(systemName: family.systemImage)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(width: 40, height: 40)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(family.label)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(family.tagline)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    let preset = PresetCatalog.presets(for: family).first
                    Tag(
                        text: preset?.geometry.sectors.formatted(.number.grouping(.automatic)) ?? "—",
                        color: Theme.mint
                    )
                    Text("sectors")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent projects")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                if !model.recentProjects.isEmpty {
                    Button("Clear") { model.clearRecents() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if model.recentProjects.isEmpty {
                Card(padding: 20) {
                    HStack(spacing: 14) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(Theme.accent.opacity(0.8))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No recent projects yet")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Create a project above, or open an existing `.discproj` file.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open…") { model.presentOpenProjectPanel() }
                            .buttonStyle(SecondaryActionButtonStyle())
                    }
                }
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.recentProjects) { entry in
                        recentCard(entry)
                    }
                }
            }
        }
    }

    private func recentCard(_ entry: RecentProject) -> some View {
        Button {
            model.openProject(at: entry.url)
        } label: {
            HStack(spacing: 13) {
                DiscThumbnail(base64: entry.thumbnailPngBase64, size: 50)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(entry.url.deletingLastPathComponent().path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        FamilyBadge(family: entry.family, compact: true)
                        Text(entry.lastOpenedUtc, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        hoveredRecent == entry.id
                            ? Color.primary.opacity(0.065)
                            : Color(nsColor: .controlBackgroundColor).opacity(0.72)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveredRecent = $0 ? entry.id : nil }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            }
            Button("Remove from Recents", role: .destructive) {
                model.removeRecent(entry)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.cliDetection.hasPrefix("Not found") ? Theme.amber : Theme.mint)
                .frame(width: 6, height: 6)
            Text("Engine: \(model.cliDetection)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Link("Upstream project", destination: URL(string: "https://github.com/JiaFeiMiao-K-Cat/DiscImageStudio")!)
                .font(.system(size: 10))
            Text("GPL-3.0-or-later")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }
}
