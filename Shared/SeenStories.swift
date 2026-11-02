import Foundation

/// Headlines the screen saver has shown, so later runs can show unseen stories first.
/// Like NewsCache, the screen saver writes inside its sandbox container and the app reads that file.
enum SeenStories {
    /// Entries older than this are forgotten.
    private static let memory: TimeInterval = 7 * 24 * 3600
    private static let capacity = 3000

    private static var ownURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nyheter/seen.json")
    }

    private static var saverURL: URL {
        NyheterSettings.realHome.appendingPathComponent(
            "Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/Nyheter/seen.json")
    }

    private static func load(_ url: URL) -> [String: Date] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: url)).flatMap { try? decoder.decode([String: Date].self, from: $0) } ?? [:]
    }

    /// Title keys (Sources.titleKey) of stories shown in the last week, by this process or the screen saver.
    static func keys() -> Set<String> {
        let cutoff = Date().addingTimeInterval(-memory)
        return Set(Set([ownURL, saverURL]).flatMap { load($0).filter { $0.value > cutoff }.keys })
    }

    static func record(_ story: Story) {
        let cutoff = Date().addingTimeInterval(-memory)
        var entries = load(ownURL).filter { $0.value > cutoff }
        entries[Sources.titleKey(story.title)] = Date()
        if entries.count > capacity {
            entries = Dictionary(uniqueKeysWithValues: entries.sorted { $0.value > $1.value }.prefix(capacity).map { ($0.key, $0.value) })
        }
        let url = ownURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(entries).write(to: url, options: .atomic)
    }
}
