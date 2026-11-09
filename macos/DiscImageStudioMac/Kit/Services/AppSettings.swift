import Combine
import Foundation

@MainActor
public final class AppSettings: ObservableObject {
    private enum Keys {
        static let cliPath = "DISCImageStudioCLIPath"
        static let defaultProjectsDirectory = "DISCImageStudioDefaultProjectsDirectory"
        static let previewSize = "DISCImageStudioPreviewSize"
        static let defaultVolumeLabel = "DISCImageStudioDefaultVolumeLabel"
    }

    @Published public var cliPath: String {
        didSet { UserDefaults.standard.set(cliPath, forKey: Keys.cliPath) }
    }

    @Published public var defaultProjectsDirectory: String {
        didSet { UserDefaults.standard.set(defaultProjectsDirectory, forKey: Keys.defaultProjectsDirectory) }
    }

    @Published public var previewSize: Int {
        didSet { UserDefaults.standard.set(previewSize, forKey: Keys.previewSize) }
    }

    @Published public var defaultVolumeLabel: String {
        didSet { UserDefaults.standard.set(defaultVolumeLabel, forKey: Keys.defaultVolumeLabel) }
    }

    public init() {
        let defaults = UserDefaults.standard
        cliPath = defaults.string(forKey: Keys.cliPath) ?? ""
        defaultProjectsDirectory = defaults.string(forKey: Keys.defaultProjectsDirectory)
            ?? AppPaths.defaultProjectsDirectory.path
        let storedSize = defaults.integer(forKey: Keys.previewSize)
        previewSize = storedSize > 0 ? storedSize : 1600
        defaultVolumeLabel = defaults.string(forKey: Keys.defaultVolumeLabel) ?? "DISC_IMAGE"
    }

    public var defaultProjectsURL: URL {
        URL(fileURLWithPath: (defaultProjectsDirectory as NSString).expandingTildeInPath)
    }

    public func resetCLIPath() {
        cliPath = ""
    }
}
