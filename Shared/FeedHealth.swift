import Foundation

/// How each feed did in recent fetches, so the app can point out feeds that broke, went quiet or
/// stopped answering. Both the screen saver and the app's preview record; the app reads both.
struct FeedStatus: Codable, Equatable {
    enum Problem: String, Codable {
        case offline     // no answer (network error or timeout)
        case http        // answered with an error code
        case empty       // answered, but nothing Nyheter could read
    }

    var url: String
    var lastTry: Date
    var lastOK: Date?
    var stories = 0              // in the last good answer
    var newest: Date?            // newest story in the last good answer
    var failures = 0             // failed tries in a row
    var problem: Problem?
    var code: Int?               // HTTP status of the last failed try

    enum State: Equatable { case ok, quiet, failing, broken }

    /// Stories older than this make a feed "quiet"; SCB publishes rarely, so it gets longer.
    static func quietLimit(for feed: String) -> TimeInterval { feed == "scb" ? 45 * 86400 : 3 * 86400 }

    func state(feed: String, now: Date = Date()) -> State {
        if failures >= 2, problem == .empty || (problem == .http && (code ?? 0) < 500) { return .broken }
        if failures >= 1 { return .failing }
        if let newest, now.timeIntervalSince(newest) > Self.quietLimit(for: feed) { return .quiet }
        return .ok
    }
}

enum FeedHealth {
    private static var ownURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nyheter/health.json")
    }

    private static var appURL: URL {
        NyheterSettings.realHome.appendingPathComponent("Library/Application Support/Nyheter/health.json")
    }

    private static var saverURL: URL {
        NyheterSettings.realHome.appendingPathComponent(
            "Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/Nyheter/health.json")
    }

    private static func load(_ url: URL) -> [String: FeedStatus] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: url)).flatMap { try? decoder.decode([String: FeedStatus].self, from: $0) } ?? [:]
    }

    /// The most recent status of every feed, from whichever process tried it last.
    static func statuses() -> [String: FeedStatus] {
        var out: [String: FeedStatus] = [:]
        for (feed, status) in Set([ownURL, appURL, saverURL]).flatMap({ load($0) }) where (out[feed]?.lastTry ?? .distantPast) < status.lastTry {
            out[feed] = status
        }
        return out
    }

    /// One fetch's outcome per feed.
    enum Outcome {
        case ok(stories: Int, newest: Date?)
        case failed(FeedStatus.Problem, code: Int?)
    }

    static func record(_ outcomes: [String: (url: URL, outcome: Outcome)], at date: Date = Date()) {
        var all = load(ownURL)
        for (feed, result) in outcomes {
            var status = all[feed] ?? FeedStatus(url: result.url.absoluteString, lastTry: date)
            status.url = result.url.absoluteString
            status.lastTry = date
            switch result.outcome {
            case let .ok(stories, newest):
                status.lastOK = date
                status.stories = stories
                status.newest = newest
                status.failures = 0
                status.problem = nil
                status.code = nil
            case let .failed(problem, code):
                status.failures += 1
                status.problem = problem
                status.code = code
            }
            all[feed] = status
        }
        let url = ownURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(all).write(to: url, options: .atomic)
    }
}
