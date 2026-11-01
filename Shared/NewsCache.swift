import Foundation

/// The last successful fetch, saved so a new start shows news at once and only fetches
/// again when the saved copy is older than the refresh interval.
/// Like BlockLog, each process writes its own file (the screen saver can only write inside
/// its sandbox container) and reads whichever of the two is newest.
struct NewsCache: Codable {
    let fetchedAt: Date
    /// Sources.requests signature at fetch time; a different one means the saved news is for other feeds.
    let signature: String
    let stories: [Story]

    /// This process's file: ~/Library/Application Support for the app, the sandbox container for the screen saver.
    private static var ownURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nyheter/news.json")
    }

    private static var appURL: URL {
        NyheterSettings.realHome.appendingPathComponent("Library/Application Support/Nyheter/news.json")
    }

    private static var saverURL: URL {
        NyheterSettings.realHome.appendingPathComponent(
            "Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/Nyheter/news.json")
    }

    /// The newest saved fetch from either process, if any.
    static func loadNewest() -> NewsCache? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return Set([ownURL, appURL, saverURL]).compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? decoder.decode(NewsCache.self, from: $0) }
        }.max { $0.fetchedAt < $1.fetchedAt }
    }

    func save() {
        let url = Self.ownURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(self).write(to: url, options: .atomic)
    }
}
