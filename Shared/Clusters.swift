import Foundation

/// The same event reported by several sources, found by the rare words their headlines and
/// first lines share. Names and numbers are spelled alike in most languages, so a Swedish and an
/// English report of the same event usually end up together.
struct StoryCluster {
    /// Oldest first.
    let stories: [Story]
    /// Each source once, in the order it first reported, with that time.
    let reports: [(source: String, date: Date)]

    var id: String { Sources.titleKey(stories[0].title) }
    var first: Date { reports[0].date }

    /// The report to show: one in the given language if there is one (with text, if possible), else the first.
    func lead(language: String) -> Story {
        let own = stories.filter { Sources.provider($0.source)?.language == language }
        return own.first { !$0.body.isEmpty } ?? own.first ?? stories.first { !$0.body.isEmpty } ?? stories[0]
    }

    /// Minutes from the first report until `count` sources had it.
    func minutes(toReach count: Int) -> Int {
        guard reports.count >= count else { return 0 }
        return Int((reports[count - 1].date.timeIntervalSince(first) / 60).rounded())
    }
}

enum Clusters {
    /// Stories further apart than this are never the same event.
    private static let window: TimeInterval = 12 * 3600
    /// Sum of the shared words' rarity (inverse document frequency) needed to link two stories.
    private static let threshold = 9.0
    /// A big story stays a takeover for this long after its first report.
    static let takeoverLifetime: TimeInterval = 3 * 3600

    /// Groups of at least two stories that report the same event.
    static func find(_ stories: [Story]) -> [StoryCluster] {
        var keys = Set<String>()
        let list = stories.filter { $0.date != .distantPast && keys.insert(Sources.titleKey($0.title)).inserted }
        let words = list.map { terms($0) }
        let titles = list.map { terms($0, titleOnly: true) }
        var frequency: [String: Int] = [:]
        for set in words { for word in set { frequency[word, default: 0] += 1 } }
        let total = Double(max(list.count, 2))
        func rarity(_ word: String) -> Double { log(total / Double(frequency[word] ?? 1)) }

        // Pairs that look like the same event: their headlines share a word, and together with the
        // first lines they share enough rare ones.
        var links: [(i: Int, j: Int, score: Double)] = []
        for i in list.indices {
            for j in list.indices where j > i && abs(list[i].date.timeIntervalSince(list[j].date)) < window {
                let shared = words[i].intersection(words[j])
                guard shared.count >= 2, !titles[i].isDisjoint(with: titles[j]) else { continue }
                let score = shared.reduce(0) { $0 + rarity($1) }
                if score >= threshold { links.append((i, j, score)) }
            }
        }
        // Strongest links first; two groups only join when most of their members are linked to each
        // other, so a chain of loosely related stories doesn't snowball into one group.
        let linked = Set(links.map { [$0.i, $0.j] })
        var group = Array(list.indices)
        var members = list.indices.map { [$0] }
        for link in links.sorted(by: { $0.score > $1.score }) {
            let a = group[link.i], b = group[link.j]
            guard a != b else { continue }
            let pairs = members[a].reduce(0) { sum, x in sum + members[b].filter { linked.contains([min(x, $0), max(x, $0)]) }.count }
            guard Double(pairs) >= 0.5 * Double(members[a].count * members[b].count) else { continue }
            for x in members[b] { group[x] = a }
            members[a] += members[b]
            members[b] = []
        }

        return members.filter { !$0.isEmpty }.compactMap { members in
            guard members.count > 1 else { return nil }
            let sorted = members.map { list[$0] }.sorted { $0.date < $1.date }
            var seen = Set<String>()
            let reports = sorted.filter { seen.insert($0.source).inserted }.map { (source: $0.source, date: $0.date) }
            return StoryCluster(stories: sorted, reports: reports)
        }
    }

    /// The biggest story that enough sources picked up fast enough, if one is still fresh.
    static func takeover(_ stories: [Story], settings s: NyheterSettings, now: Date = Date()) -> StoryCluster? {
        guard s.takeover else { return nil }
        let needed = max(2, s.takeoverSources)
        return find(stories).filter { cluster in
            cluster.reports.count >= needed
                && cluster.reports[needed - 1].date.timeIntervalSince(cluster.first) <= Double(s.takeoverMinutes) * 60
                && now.timeIntervalSince(cluster.first) <= takeoverLifetime
        }.max { ($0.reports.count, $0.first) < ($1.reports.count, $1.first) }
    }

    /// Words that can tell one event from another: four letters or more (cut to six, so
    /// "Ukraina" and "Ukraine" meet), and numbers of two digits or more; common words left out.
    static func terms(_ story: Story, titleOnly: Bool = false) -> Set<String> {
        let text = titleOnly ? story.title : story.title + " " + (story.body.first.map { String($0.prefix(200)) } ?? "")
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var out = Set<String>()
        for word in folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            if word.allSatisfy(\.isNumber) {
                if word.count >= 2 { out.insert(String(word)) }
            } else if word.count >= 4, !stopwords.contains(String(word)) {
                out.insert(String(word.prefix(6)))
            }
        }
        return out
    }

    private static let stopwords = Set<String>([
        // English
        "about", "after", "again", "against", "also", "amid", "back", "been", "before", "being", "could", "does", "down", "during",
        "each", "even", "first", "from", "have", "here", "into", "just", "last", "latest", "like", "live", "make", "many", "more",
        "most", "much", "news", "only", "other", "over", "people", "report", "reports", "said", "says", "should", "some", "still",
        "than", "that", "their", "them", "then", "there", "these", "they", "this", "those", "through", "time", "today", "under",
        "until", "update", "updates", "very", "want", "were", "what", "when", "where", "which", "while", "will", "with", "would",
        "year", "years", "your", "week", "told", "take", "takes", "know", "says", "amid",
        // Swedish (folded: å, ä, ö → a, o)
        "alla", "andra", "annat", "bara", "blir", "efter", "eller", "enligt", "finns", "flera", "fran", "forsta", "fore", "genom",
        "har", "hela", "infor", "inom", "inte", "kommer", "kunde", "kvar", "manga", "mellan", "mest", "mycket", "nagon", "nagot",
        "nagra", "nar", "nara", "nyheter", "ocksa", "redan", "sade", "sager", "samma", "sedan", "sina", "sitt", "skulle", "stora",
        "till", "under", "utan", "vara", "varit", "vill", "aret", "over", "efter", "dagar", "idag", "igen", "just", "ska", "mot",
        "stor", "stort", "sista", "dessa", "detta", "denna", "dock", "hade", "hans", "hennes", "deras", "blev", "varje", "kan",
    ])
}
