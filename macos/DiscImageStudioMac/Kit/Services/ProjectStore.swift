import Foundation

public enum AppPaths {
    public static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("DiscImageStudio", isDirectory: true)
    }

    public static var caches: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        return base.appendingPathComponent("DiscImageStudio", isDirectory: true)
    }

    public static var defaultProjectsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        return documents.appendingPathComponent("DiscImageStudio Projects", isDirectory: true)
    }

    public static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

// MARK: - JSON coding

public enum ProjectJSON {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601WithFractional.string(from: date))
        }
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = parseDate(string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date, got '\(string)'."
            )
        }
        return decoder
    }()

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fallbackFormatters: [DateFormatter] = {
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        ]
        return patterns.map { pattern in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = pattern
            return formatter
        }
    }()

    static func parseDate(_ string: String) -> Date? {
        if let date = iso8601WithFractional.date(from: string) {
            return date
        }
        if let date = iso8601Plain.date(from: string) {
            return date
        }
        for formatter in fallbackFormatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }
}

// MARK: - Project persistence

public enum ProjectStore {
    public static let fileExtension = "discproj"

    public static func load(from url: URL) throws -> ProjectDocument {
        let data = try Data(contentsOf: url)
        var document: ProjectDocument
        do {
            document = try ProjectJSON.decoder.decode(ProjectDocument.self, from: data)
        } catch {
            throw ProjectValidationError.invalidProject(
                "Could not read \(url.lastPathComponent): \(readable(error))"
            )
        }
        // Schema 1 is read as its current equivalent; the next save writes schema 2.
        document.schemaVersion = ProjectDocument.currentSchemaVersion
        try document.validate()
        return document
    }

    public static func save(_ document: ProjectDocument, to url: URL) throws {
        var document = document
        document.schemaVersion = ProjectDocument.currentSchemaVersion
        try document.validate()
        let directory = url.deletingLastPathComponent()
        try AppPaths.ensureDirectory(directory)
        let data = try ProjectJSON.encoder.encode(document)
        try data.write(to: url, options: .atomic)
    }

    private static func readable(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .keyNotFound(let key, _):
                return "missing field '\(key.stringValue)'"
            case .typeMismatch(_, let context):
                return "wrong type at \(codingPath(context.codingPath))"
            case .valueNotFound(_, let context):
                return "missing value at \(codingPath(context.codingPath))"
            case .dataCorrupted(let context):
                return context.debugDescription
            @unknown default:
                return error.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private static func codingPath(_ path: [CodingKey]) -> String {
        path.map(\.stringValue).joined(separator: ".")
    }
}

// MARK: - Recent projects

public struct RecentProject: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var discFamily: String
    public var projectPath: String
    public var thumbnailPngBase64: String?
    public var lastOpenedUtc: Date

    public var id: String { projectPath }
    public var url: URL { URL(fileURLWithPath: projectPath) }
    public var family: DiscFamily {
        switch discFamily.lowercased() {
        case "dvd": return .dvd
        case "bd": return .bd
        default: return .cd
        }
    }

    public init(
        name: String,
        discFamily: String,
        projectPath: String,
        thumbnailPngBase64: String? = nil,
        lastOpenedUtc: Date = Date()
    ) {
        self.name = name
        self.discFamily = discFamily
        self.projectPath = projectPath
        self.thumbnailPngBase64 = thumbnailPngBase64
        self.lastOpenedUtc = lastOpenedUtc
    }
}

public final class RecentProjectsStore {
    public static let maxEntries = 12
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AppPaths.applicationSupport.appendingPathComponent("recent-projects.json")
    }

    public func load() -> [RecentProject] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? ProjectJSON.decoder.decode([RecentProject].self, from: data)
        else { return [] }
        return sanitize(entries)
    }

    public func record(_ entry: RecentProject) {
        var entries = load().filter { $0.projectPath != entry.projectPath }
        entries.insert(entry, at: 0)
        save(Array(entries.prefix(RecentProjectsStore.maxEntries)))
    }

    public func remove(path: String) {
        save(load().filter { $0.projectPath != path })
    }

    public func clear() {
        save([])
    }

    private func sanitize(_ entries: [RecentProject]) -> [RecentProject] {
        var seen = Set<String>()
        var result: [RecentProject] = []
        for entry in entries.sorted(by: { $0.lastOpenedUtc > $1.lastOpenedUtc }) {
            guard !entry.name.isEmpty,
                  !entry.projectPath.isEmpty,
                  seen.insert(entry.projectPath).inserted
            else { continue }
            result.append(entry)
            if result.count == RecentProjectsStore.maxEntries { break }
        }
        return result
    }

    private func save(_ entries: [RecentProject]) {
        do {
            try AppPaths.ensureDirectory(fileURL.deletingLastPathComponent())
            let data = try ProjectJSON.encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Recents are a convenience; failing to write them must never fail a project.
        }
    }
}
