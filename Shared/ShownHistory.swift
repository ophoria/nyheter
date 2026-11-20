import Foundation

/// A story the screen saver showed, for the History window and the menu bar.
struct ShownEntry: Codable, Identifiable, Equatable {
    let title: String
    let source: String
    let category: String
    let link: URL?
    let published: Date
    var shownAt: Date
    var id: String { Sources.titleKey(title) }
}

/// Everything the screen saver showed in the last week, newest first.
/// Like SeenStories, the screen saver writes inside its sandbox container and the app reads that file.
enum ShownHistory {
    private static let memory: TimeInterval = 7 * 24 * 3600
    private static let capacity = 2000

    private static var ownURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nyheter/history.json")
    }

    private static var saverURL: URL {
        NyheterSettings.realHome.appendingPathComponent(
            "Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/Nyheter/history.json")
    }

    private static func load(_ url: URL) -> [ShownEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: url)).flatMap { try? decoder.decode([ShownEntry].self, from: $0) } ?? []
    }

    /// The last week's stories, newest first; a story shown several times appears once, at its latest showing.
    static func entries() -> [ShownEntry] {
        let cutoff = Date().addingTimeInterval(-memory)
        var latest: [String: ShownEntry] = [:]
        for entry in Set([ownURL, saverURL]).flatMap(load) where entry.shownAt > cutoff {
            if (latest[entry.id]?.shownAt ?? .distantPast) < entry.shownAt { latest[entry.id] = entry }
        }
        return latest.values.sorted { $0.shownAt > $1.shownAt }
    }

    /// When the screen saver last wrote its history (the app reloads when this changes).
    static var modified: Date? {
        [ownURL, saverURL].compactMap { (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date }.max()
    }

    static func record(_ story: Story) {
        let cutoff = Date().addingTimeInterval(-memory)
        let entry = ShownEntry(title: story.title, source: story.source, category: story.category, link: story.link,
                               published: story.date, shownAt: Date())
        var list = load(ownURL).filter { $0.shownAt > cutoff && $0.id != entry.id }
        list.insert(entry, at: 0)
        if list.count > capacity { list = Array(list.prefix(capacity)) }
        let url = ownURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(list).write(to: url, options: .atomic)
    }
}
