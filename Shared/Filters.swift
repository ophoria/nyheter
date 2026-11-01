import Foundation

/// Hides stories whose headline and/or text matches a word or regular expression.
struct NewsFilter: Codable, Identifiable, Equatable {
    enum Scope: String, Codable, CaseIterable {
        case both, title, body
    }

    /// Default filter: dated round-ups such as "26 oktober: Nattens nyheter".
    static let dateRoundups = NewsFilter(
        pattern: #"\b\d{1,2}\s+(januari|februari|mars|april|maj|juni|juli|augusti|september|oktober|november|december)\s*:"#,
        regex: true, scope: .title, language: "sv")

    /// Default filter: entertainment and culture vocabulary, tuned against SVT/SR/DN to spare ordinary news.
    static let entertainment = NewsFilter(
        pattern: #"(fotboll|allsvensk|sångare|sångerska|artist|musiker|rappare|låtskrivare|kompositör|dirigent|författare|poet|\broman(en|er|erna)?\b|litteratur|bokmässa|skådespel|filmstjärna|filmfestival|skräckfilm|\bbio(graf|premiär)|guldbagge|oscars|melodifestival|\bmello\b|eurovision|grammis|\bidol\b|let.s dance|programledare|realityserie|dokusåpa|\bgvfö\b|influencer|kändis|kulturdebatt|kulturhus|kulturpris|kulturprofil|svenska akademien|konstnär|utställning|musikal|\bopera(n|sångare)?\b|teaterpjäs|\bteatern\b|konsert|turné|\balbum|\bskiva\b|\bsingel\b|låtar\b|låten\b|recension|nöjesprofil|nöjesliv)"#,
        regex: true, language: "sv")

    var id = UUID()
    var pattern: String
    var regex = false
    var caseSensitive = false
    var scope = Scope.both
    var enabled = true
    /// Only applies to sources in this language (e.g. "sv" for Swedish word lists); nil = all.
    var language: String?

    /// The compiled expression; plain text is matched literally. Nil when a regex doesn't compile.
    var expression: NSRegularExpression? {
        guard !pattern.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: regex ? pattern : NSRegularExpression.escapedPattern(for: pattern),
                                        options: caseSensitive ? [] : [.caseInsensitive])
    }

    /// Why a regex doesn't compile, for showing in the app.
    var error: String? {
        guard regex, !pattern.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: pattern)
            return nil
        } catch {
            return (error as NSError).userInfo["NSInvalidValue"].map { L("Invalid expression: %@", "\($0)") } ?? L("Invalid regular expression")
        }
    }

    struct Match: Equatable {
        let place: String     // "title" or "body"
        let text: String      // the words that matched, e.g. "fotbollen"
    }

    /// Where and on what the filter matches the story, or nil. Results are cached per
    /// filter and story: a long alternation over hundreds of stories takes ~0.3 s to evaluate.
    func match(_ story: Story, using expression: NSRegularExpression) -> Match? {
        let key = "\(regex)\(caseSensitive)\(scope.rawValue)\u{1}\(pattern)\u{1}\(story.feed)\u{1}\(story.title)"
        if let cached = MatchCache.get(key) { return cached }
        let result = evaluate(story, using: expression)
        MatchCache.set(key, result)
        return result
    }

    private func evaluate(_ story: Story, using expression: NSRegularExpression) -> Match? {
        func hit(_ s: String) -> String? {
            guard let m = expression.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range, in: s) else { return nil }
            return String(s[r])
        }
        if scope != .body, let text = hit(story.title) { return Match(place: "title", text: text) }
        if scope != .title, let text = hit(story.body.joined(separator: " ")) { return Match(place: "body", text: text) }
        return nil
    }
}

/// Thread-safe memo of filter results; cleared when it grows large (old stories drop out of the feeds).
private enum MatchCache {
    private static var values: [String: NewsFilter.Match?] = [:]
    private static let lock = NSLock()

    static func get(_ key: String) -> NewsFilter.Match?? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    static func set(_ key: String, _ value: NewsFilter.Match?) {
        lock.lock(); defer { lock.unlock() }
        if values.count > 50_000 { values.removeAll() }
        values[key] = .some(value)
    }
}

enum Filters {
    static let sectionPrefix = "Section: "

    /// A logged pattern for display; section blocks are shown in the app's language.
    static func displayPattern(_ pattern: String) -> String {
        for prefix in [sectionPrefix, "Sektion: "] where pattern.hasPrefix(prefix) {
            return L("Section: %@", L(String(pattern.dropFirst(prefix.count))))
        }
        return pattern
    }

    /// Where a logged match was found, for display (older log entries used Swedish words).
    static func displayPlace(_ place: String) -> String {
        switch place {
        case "title", "rubrik": return L("in the headline")
        case "body", "text": return L("in the text")
        default: return L("in the section")
        }
    }

    struct Hit {
        let story: Story
        let filter: NewsFilter
        let place: String
        let matched: String
    }

    /// Splits stories into those kept and those hidden by a blocked section or the first matching enabled filter.
    static func apply(_ stories: [Story], _ filters: [NewsFilter], sections: [String] = []) -> (kept: [Story], hits: [Hit]) {
        let active = filters.filter(\.enabled).compactMap { filter in filter.expression.map { (filter, $0) } }
        let blocked = Set(sections)
        guard !active.isEmpty || !blocked.isEmpty else { return (stories, []) }
        var kept: [Story] = []
        var hits: [Hit] = []
        for story in stories {
            let storyLanguage = Sources.provider(story.source)?.language
            if blocked.contains(story.category) {
                hits.append(Hit(story: story, filter: NewsFilter(pattern: sectionPrefix + story.category), place: "section", matched: L(story.category)))
            } else if let hit = active.lazy.filter({ f, _ in f.language == nil || f.language == storyLanguage })
                        .compactMap({ f, re in f.match(story, using: re).map { Hit(story: story, filter: f, place: $0.place, matched: $0.text) } }).first {
                hits.append(hit)
            } else {
                kept.append(story)
            }
        }
        return (kept, hits)
    }
}

/// A story that a filter hid, as kept in the log.
struct BlockedEntry: Codable, Identifiable, Equatable {
    var id: String { key }
    let key: String
    let blockedAt: Date
    let source: String
    let feed: String
    let title: String
    let link: URL?
    let pattern: String
    let place: String
    /// The text that triggered the filter (nil in entries logged before this was recorded).
    var matched: String? = nil
}

/// Log of filtered stories: a ring of 1000 entries where the newest replace the oldest.
/// Each process writes its own file (the screen saver can only write inside its sandbox
/// container); the app shows both merged.
enum BlockLog {
    static let capacity = 1000

    /// This process's log: ~/Library/Application Support for the app, the sandbox container for the screen saver.
    static var ownURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nyheter/blocked.json")
    }

    static var saverURL: URL {
        NyheterSettings.realHome.appendingPathComponent(
            "Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/Nyheter/blocked.json")
    }

    static func load(_ url: URL) -> [BlockedEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([BlockedEntry].self, from: data)) ?? []
    }

    private static func save(_ entries: [BlockedEntry], to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(entries).write(to: url, options: .atomic)
    }

    /// Adds new hits (each story + filter once), dropping the oldest beyond the capacity.
    static func record(_ hits: [Filters.Hit], clearedAt: Date?) {
        var entries = load(ownURL).filter { clearedAt == nil || $0.blockedAt > clearedAt! }
        var known = Set(entries.map(\.key))
        let now = Date()
        var added = false
        for hit in hits {
            let key = hit.story.title + "|" + hit.filter.pattern
            guard known.insert(key).inserted else {
                // Entries logged before matched words were recorded get theirs filled in.
                if let i = entries.firstIndex(where: { $0.key == key && $0.matched == nil }) {
                    entries[i].matched = hit.matched
                    added = true
                }
                continue
            }
            entries.append(BlockedEntry(key: key, blockedAt: now, source: hit.story.source, feed: hit.story.feed,
                                        title: hit.story.title, link: hit.story.link, pattern: hit.filter.pattern, place: hit.place,
                                        matched: hit.matched))
            added = true
        }
        guard added else { return }
        save(Array(entries.suffix(capacity)), to: ownURL)
    }

    /// Both logs merged, newest first, at most `capacity` entries.
    static func loadAll(clearedAt: Date?) -> [BlockedEntry] {
        var byKey: [String: BlockedEntry] = [:]
        for entry in load(ownURL) + load(saverURL) where clearedAt == nil || entry.blockedAt > clearedAt! {
            if let existing = byKey[entry.key], existing.blockedAt <= entry.blockedAt { continue }
            byKey[entry.key] = entry
        }
        return Array(byKey.values.sorted { $0.blockedAt > $1.blockedAt }.prefix(capacity))
    }

    static func clear() { save([], to: ownURL) }

    /// When an entry was filtered out, to the second, in the app's language.
    static func timestamp(_ date: Date) -> String {
        date.formatted(.dateTime.locale(L10n.locale).day().month(.abbreviated).hour().minute().second())
    }
}
