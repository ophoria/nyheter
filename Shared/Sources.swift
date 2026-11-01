import Foundation

/// A news outlet the app can show: its feeds, the sections it uses and what can be configured for it.
/// The app's settings only show providers the user has switched on.
struct Provider: Identifiable {
    enum Style { case svt, sr, dn, scb, nyt, bbc, msnow }

    struct Feed: Identifiable {
        let id: String
        let name: String          // English key for L()
        let url: String
        var section: String? = nil // section for every story in this feed, if the links don't tell
        var defaultOn = false
    }

    let id: String
    let name: String
    let label: String              // short name on the slide chip
    let language: String           // "sv", "en"
    let country: String            // "SE", "US", "GB"
    let style: Style
    let feeds: [Feed]
    let sections: [String]         // sections its stories can have (see Sources.sectionOrder)
    var defaultEnabled = false
    var localRegions = false       // SVT: regional news with a choice of regions
    var itemLimit = false          // SCB: few, slow-moving items with their own cap

    var flag: String { ["SE": "🇸🇪", "US": "🇺🇸", "GB": "🇬🇧"][country] ?? "🏳️" }
}

struct Story: Codable {
    let source: String            // provider id, or "world" for the counter slide
    let feed: String
    let title: String
    let body: [String]
    let bullets: Bool
    let date: Date
    let category: String
    let imageURL: URL?
    var region: String? = nil
    /// The story's page on the source's own site.
    var link: URL? = nil
}

struct FeedRequest {
    let source: String
    let feed: String
    let url: URL
    let parse: (Data) -> [Story]
}

enum Sources {
    static let svtLocalFeed = "svt-local"

    static let providers: [Provider] = [
        Provider(id: "svt", name: "SVT Nyheter", label: "SVT", language: "sv", country: "SE", style: .svt, feeds: [
            .init(id: "svt-top", name: "Top stories", url: "https://www.svt.se/nyheter/rss.xml", defaultOn: true),
            .init(id: "svt-inrikes", name: "Domestic", url: "https://www.svt.se/nyheter/inrikes/rss.xml"),
            .init(id: "svt-utrikes", name: "Foreign", url: "https://www.svt.se/nyheter/utrikes/rss.xml"),
            .init(id: svtLocalFeed, name: "Local news", url: "", defaultOn: true),
        ], sections: ["Inrikes", "Utrikes", "Ekonomi", "Kultur", "Vetenskap", "Politik", "Klimat", "Granskning", "Nöje", "Sport", "Uutiset", "Sápmi"],
           defaultEnabled: true, localRegions: true),
        Provider(id: "sr", name: "Sveriges Radio", label: "SR Ekot", language: "sv", country: "SE", style: .sr, feeds: [
            .init(id: "sr-ekot", name: "Ekot", url: "https://api.sr.se/api/rss/program/83", defaultOn: true),
        ], sections: [], defaultEnabled: true),
        Provider(id: "dn", name: "Dagens Nyheter", label: "DN", language: "sv", country: "SE", style: .dn, feeds: [
            .init(id: "dn-top", name: "Top stories", url: "https://www.dn.se/rss/", defaultOn: true),
            .init(id: "dn-sverige", name: "Sweden", url: "https://www.dn.se/rss/sverige/"),
            .init(id: "dn-varlden", name: "World", url: "https://www.dn.se/rss/varlden/"),
        ], sections: ["Sverige", "Världen", "Ekonomi", "Kultur", "Sport", "Debatt", "Ledare", "Insändare", "Podd", "Motor"]),
        Provider(id: "scb", name: "SCB", label: "SCB", language: "sv", country: "SE", style: .scb, feeds: [
            .init(id: "scb", name: "Statistics news", url: "https://www.scb.se/feed/statistiknyheter/", section: "Statistik", defaultOn: true),
        ], sections: ["Statistik"], itemLimit: true),
        Provider(id: "nyt", name: "The New York Times", label: "NYT", language: "en", country: "US", style: .nyt, feeds: [
            .init(id: "nyt-top", name: "Top stories", url: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml", defaultOn: true),
            .init(id: "nyt-world", name: "World", url: "https://rss.nytimes.com/services/xml/rss/nyt/World.xml", section: "Världen"),
            .init(id: "nyt-us", name: "U.S.", url: "https://rss.nytimes.com/services/xml/rss/nyt/US.xml", section: "USA"),
            .init(id: "nyt-politics", name: "Politics", url: "https://rss.nytimes.com/services/xml/rss/nyt/Politics.xml", section: "Politik"),
            .init(id: "nyt-business", name: "Business", url: "https://rss.nytimes.com/services/xml/rss/nyt/Business.xml", section: "Ekonomi"),
            .init(id: "nyt-technology", name: "Technology", url: "https://rss.nytimes.com/services/xml/rss/nyt/Technology.xml", section: "Teknik"),
            .init(id: "nyt-science", name: "Science", url: "https://rss.nytimes.com/services/xml/rss/nyt/Science.xml", section: "Vetenskap"),
            .init(id: "nyt-health", name: "Health", url: "https://rss.nytimes.com/services/xml/rss/nyt/Health.xml", section: "Hälsa"),
            .init(id: "nyt-arts", name: "Arts", url: "https://rss.nytimes.com/services/xml/rss/nyt/Arts.xml", section: "Kultur"),
            .init(id: "nyt-opinion", name: "Opinion", url: "https://rss.nytimes.com/services/xml/rss/nyt/Opinion.xml", section: "Debatt"),
        ], sections: ["USA", "Världen", "Politik", "Ekonomi", "Teknik", "Vetenskap", "Klimat", "Hälsa", "Kultur", "Sport", "Debatt", "Livsstil"]),
        Provider(id: "bbc", name: "BBC News", label: "BBC", language: "en", country: "GB", style: .bbc, feeds: [
            .init(id: "bbc-top", name: "Top stories", url: "https://feeds.bbci.co.uk/news/rss.xml", defaultOn: true),
            .init(id: "bbc-world", name: "World", url: "https://feeds.bbci.co.uk/news/world/rss.xml", section: "Världen"),
            .init(id: "bbc-uk", name: "UK", url: "https://feeds.bbci.co.uk/news/uk/rss.xml", section: "Storbritannien"),
            .init(id: "bbc-politics", name: "Politics", url: "https://feeds.bbci.co.uk/news/politics/rss.xml", section: "Politik"),
            .init(id: "bbc-business", name: "Business", url: "https://feeds.bbci.co.uk/news/business/rss.xml", section: "Ekonomi"),
            .init(id: "bbc-technology", name: "Technology", url: "https://feeds.bbci.co.uk/news/technology/rss.xml", section: "Teknik"),
            .init(id: "bbc-science", name: "Science & environment", url: "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml", section: "Vetenskap"),
            .init(id: "bbc-health", name: "Health", url: "https://feeds.bbci.co.uk/news/health/rss.xml", section: "Hälsa"),
            .init(id: "bbc-arts", name: "Entertainment & arts", url: "https://feeds.bbci.co.uk/news/entertainment_and_arts/rss.xml", section: "Kultur"),
            .init(id: "bbc-sport", name: "Sport", url: "https://feeds.bbci.co.uk/sport/rss.xml", section: "Sport"),
        ], sections: ["Världen", "Storbritannien", "Politik", "Ekonomi", "Teknik", "Vetenskap", "Hälsa", "Kultur", "Sport"]),
        Provider(id: "msnow", name: "MS NOW (MSNBC)", label: "MS NOW", language: "en", country: "US", style: .msnow, feeds: [
            .init(id: "msnow-latest", name: "Latest", url: "https://www.ms.now/feed", defaultOn: true),
            .init(id: "msnow-news", name: "News", url: "https://www.ms.now/category/news/feed"),
            .init(id: "msnow-politics", name: "Politics", url: "https://www.ms.now/category/politics/feed", section: "Politik"),
            .init(id: "msnow-opinion", name: "Opinion", url: "https://www.ms.now/category/opinion/feed", section: "Debatt"),
        ], sections: ["Politik", "Debatt"]),
    ]

    static let providerIDs = providers.map(\.id)

    static func provider(_ id: String) -> Provider? { providers.first { $0.id == id } }

    /// Short name for a story's source, e.g. "SVT"; the counter slide is "World".
    static func label(_ id: String) -> String { id == "world" ? L("World") : provider(id)?.label ?? id }

    static let svtRegions: [(slug: String, name: String)] = [
        ("blekinge", "Blekinge"), ("dalarna", "Dalarna"), ("gavleborg", "Gävleborg"), ("halland", "Halland"),
        ("helsingborg", "Helsingborg"), ("jamtland", "Jämtland"), ("jonkoping", "Jönköping"),
        ("norrbotten", "Norrbotten"), ("skane", "Skåne"), ("smaland", "Småland"), ("sodertalje", "Södertälje"),
        ("sormland", "Sörmland"), ("stockholm", "Stockholm"), ("uppsala", "Uppsala"), ("varmland", "Värmland"),
        ("vast", "Väst"), ("vasterbotten", "Västerbotten"), ("vasternorrland", "Västernorrland"),
        ("vastmanland", "Västmanland"), ("orebro", "Örebro"), ("ost", "Öst"),
    ]
    private static let regionNames = Dictionary(uniqueKeysWithValues: svtRegions.map { ($0.slug, $0.name) })

    /// Path segments in SVT/DN links → section.
    private static let swedishSections = [
        "inrikes": "Inrikes", "utrikes": "Utrikes", "ekonomi": "Ekonomi", "kultur": "Kultur",
        "vetenskap": "Vetenskap", "politik": "Politik", "klimat": "Klimat", "granskning": "Granskning",
        "nojesliv": "Nöje", "sverige": "Sverige", "varlden": "Världen", "sport": "Sport", "debatt": "Debatt",
        "ledare": "Ledare", "nyheter": "Nyheter", "insandare": "Insändare", "podd": "Podd", "motor": "Motor",
        "uutiset": "Uutiset", "sapmi": "Sápmi",
    ]
    /// Path segments in NYT / MS NOW links → section.
    private static let englishSections = [
        "us": "USA", "nyregion": "USA", "world": "Världen", "politics": "Politik", "upshot": "Politik",
        "business": "Ekonomi", "realestate": "Ekonomi", "technology": "Teknik", "science": "Vetenskap",
        "climate": "Klimat", "health": "Hälsa", "well": "Hälsa", "arts": "Kultur", "books": "Kultur", "movies": "Kultur",
        "theater": "Kultur", "sports": "Sport", "athletic": "Sport", "opinion": "Debatt", "style": "Livsstil",
        "magazine": "Livsstil", "travel": "Livsstil", "dining": "Livsstil", "briefing": "Nyheter", "news": "Nyheter",
    ]

    /// Sections offered for blocking, most likely to be unwanted first. Section names are
    /// stable keys (in Swedish, as first used); the app shows them translated.
    static let sectionOrder = ["Kultur", "Nöje", "Sport", "Debatt", "Ledare", "Insändare", "Livsstil", "Podd", "Motor",
                               "Ekonomi", "Teknik", "Vetenskap", "Hälsa", "Klimat", "Politik", "Granskning",
                               "Inrikes", "Utrikes", "Sverige", "USA", "Storbritannien", "Världen", "Statistik", "Uutiset", "Sápmi"]

    /// Sections used by the providers the user has switched on.
    static func sections(for s: NyheterSettings) -> [String] {
        let used = Set(providers.filter { s.isEnabled($0.id) }.flatMap(\.sections))
        return sectionOrder.filter(used.contains)
    }

    static func requests(for s: NyheterSettings) -> [FeedRequest] {
        var out: [FeedRequest] = []
        for provider in providers where s.isEnabled(provider.id) {
            let config = s.source(provider.id)
            func add(_ feed: Provider.Feed, url: String? = nil, id: String? = nil) {
                let feedID = id ?? feed.id
                out.append(FeedRequest(source: provider.id, feed: feedID, url: URL(string: url ?? feed.url)!,
                                       parse: { parse($0, provider: provider, feed: feed, feedID: feedID) }))
            }
            for feed in provider.feeds where feed.id != svtLocalFeed && s.isOn(feed, of: provider) { add(feed) }
            if provider.localRegions, let local = provider.feeds.first(where: { $0.id == svtLocalFeed }), s.isOn(local, of: provider) {
                if config.regions.isEmpty {
                    // The top feed also carries regional stories, so it is needed for "local, any region".
                    if let top = provider.feeds.first, !s.isOn(top, of: provider) { add(top) }
                } else {
                    for slug in config.regions {
                        add(local, url: "https://www.svt.se/nyheter/lokalt/\(slug)/rss.xml", id: "svt-\(slug)")
                    }
                }
            }
        }
        return out
    }

    /// Filters, dedupes and caps each source, then orders them by the chosen mode.
    static func assemble(_ fetched: [Story], settings s: NyheterSettings) -> [Story] {
        var bySource: [String: [Story]] = [:]
        for story in fetched where s.isEnabled(story.source) { bySource[story.source, default: []].append(story) }

        for (id, list) in bySource {
            guard let provider = provider(id) else { continue }
            let config = s.source(id)
            // Newest first; a story found in several feeds keeps the copy with a real section.
            var seen = Set<String>()
            var stories = list.sorted { ($0.date, $0.category != "Nyheter" ? 1 : 0) > ($1.date, $1.category != "Nyheter" ? 1 : 0) }
                .filter { seen.insert($0.title).inserted }
            if provider.localRegions {
                let topOn = provider.feeds.first.map { s.isOn($0, of: provider) } ?? true
                let localOn = provider.feeds.first { $0.id == svtLocalFeed }.map { s.isOn($0, of: provider) } ?? false
                var local = 0
                stories = stories.filter { story in
                    guard let region = story.region else { return story.feed != provider.feeds.first?.id || topOn }
                    guard localOn, config.regions.isEmpty || config.regions.contains(region) else { return false }
                    local += 1
                    return local <= config.maxLocal
                }
            }
            if provider.itemLimit { stories = Array(stories.prefix(config.maxItems)) }
            bySource[id] = Array(stories.prefix(s.maxPerSource))
        }

        let enabled = providers.map(\.id).filter(s.isEnabled)
        var ordered: [Story]
        switch s.orderMode {
        case .turns:
            // Walk the pattern repeatedly, taking the next story from each source in it.
            let pattern = withMissingSources(s.turnPattern, enabled: enabled)
            var next: [String: Int] = [:]
            ordered = []
            var progressed = true
            while progressed {
                progressed = false
                for id in pattern {
                    let i = next[id, default: 0]
                    guard let list = bySource[id], i < list.count else { continue }
                    ordered.append(list[i])
                    next[id] = i + 1
                    progressed = true
                }
            }
        case .blocks:
            ordered = unique(withMissingSources(s.blockOrder, enabled: enabled)).flatMap { bySource[$0] ?? [] }
        case .random:
            ordered = bySource.values.flatMap { $0 }.shuffled()
        }

        // The same story often runs under the same headline at several outlets; keep the first.
        var seen = Set<String>()
        return Array(ordered.filter { seen.insert(titleKey($0.title)).inserted }.prefix(NyheterSettings.maxStories))
    }

    /// The enabled sources in a custom order (others are remembered but skipped),
    /// plus enabled sources left out of it, so none is silently hidden.
    static func withMissingSources(_ order: [String], enabled: [String]) -> [String] {
        order.filter(enabled.contains) + enabled.filter { !order.contains($0) }
    }

    static func unique(_ order: [String]) -> [String] {
        var seen = Set<String>()
        return order.filter { seen.insert($0).inserted }
    }

    /// Human-readable name of a feed id in the app's language, e.g. "svt-skane" → "SVT · Local: Skåne".
    static func feedName(_ feedID: String) -> String {
        for provider in providers {
            if let feed = provider.feeds.first(where: { $0.id == feedID }) { return provider.label + " · " + L(feed.name) }
        }
        let slug = feedID.replacingOccurrences(of: "svt-", with: "")
        return "SVT · " + L("Local: %@", regionNames[slug] ?? slug.capitalized)
    }

    static func parse(_ data: Data, provider: Provider, feed: Provider.Feed, feedID: String) -> [Story] {
        switch provider.style {
        case .svt: return parseSVT(data, feed: feedID)
        case .sr: return parseSR(data, feed: feedID)
        case .dn: return parseDN(data, feed: feedID)
        case .scb: return parseSCB(data, feed: feedID)
        case .nyt, .bbc, .msnow: return parseEnglish(data, provider: provider, feed: feed)
        }
    }

    // MARK: - Parsers

    static func parseSVT(_ data: Data, feed: String) -> [Story] {
        FeedParser.items(in: data).compactMap { item in
            guard let title = item["title"] else { return nil }
            let parts = pathParts(item["link"])
            var category = "Nyheter"
            var region: String?
            if parts.count > 2, parts[1] == "lokalt" {
                region = parts[2]
                category = regionNames[parts[2]] ?? parts[2].capitalized
            } else if let first = parts.first, first != "nyheter", let section = swedishSections[first] {
                category = section    // svt.se/kultur/…, svt.se/sport/…
            } else if parts.count > 1, let section = swedishSections[parts[1]] {
                category = section
            }
            return Story(source: "svt", feed: feed, title: title, body: [item["description"] ?? ""], bullets: false,
                         date: rssDate(item["pubDate"]), category: category, imageURL: nil, region: region, link: articleURL(item))
        }
    }

    static func parseSR(_ data: Data, feed: String) -> [Story] {
        FeedParser.items(in: data).compactMap { item in
            guard let title = item["title"] else { return nil }
            let summary = item["summary"] ?? ""
            var body = captures(#"<li[^>]*>(.*?)</li>"#, in: summary).map(plainText).filter { !$0.isEmpty }
            let isList = !body.isEmpty
            if !isList { body = [plainText(summary)] }
            let image = captures(#"<img[^>]+src="([^"?]+)"#, in: item["content"] ?? "").first.flatMap(URL.init(string:))
            return Story(source: "sr", feed: feed, title: title, body: Array(body.prefix(3)), bullets: isList,
                         date: isoDate(item["published"]), category: item["category"] ?? "Nyheter", imageURL: image, link: articleURL(item))
        }
    }

    static func parseDN(_ data: Data, feed: String) -> [Story] {
        FeedParser.items(in: data).compactMap { item in
            guard let title = item["title"] else { return nil }
            let section = pathParts(item["link"]).first.flatMap { swedishSections[$0] } ?? "Nyheter"
            return Story(source: "dn", feed: feed, title: title, body: [plainText(item["description"] ?? "")], bullets: false,
                         date: rssDate(item["pubDate"]), category: section, imageURL: item["image"].flatMap(URL.init(string:)), link: articleURL(item))
        }
    }

    static func parseSCB(_ data: Data, feed: String) -> [Story] {
        FeedParser.items(in: data).compactMap { item in
            guard let title = item["title"] else { return nil }
            return Story(source: "scb", feed: feed, title: title, body: [plainText(item["content"] ?? item["summary"] ?? "")],
                         bullets: false, date: isoDate(item["published"]), category: "Statistik", imageURL: nil, link: articleURL(item))
        }
    }

    /// NYT, BBC and MS NOW: plain RSS; section from the feed, else from the link path.
    static func parseEnglish(_ data: Data, provider: Provider, feed: Provider.Feed) -> [Story] {
        FeedParser.items(in: data).compactMap { item in
            guard let title = item["title"] else { return nil }
            var section = feed.section
            if section == nil, provider.style != .bbc {
                // nytimes.com/2026/11/01/us/politics/… → "politics" before "us"; ms.now/opinion/… → "opinion".
                let words = pathParts(item["link"]).filter { Int($0) == nil }.dropLast()
                section = words.reversed().lazy.compactMap { englishSections[$0] }.first
            }
            // MS NOW repeats a "The post … appeared first on" line after the summary; keep the first paragraph.
            let description = item["description"] ?? ""
            let summary = captures(#"<p[^>]*>(.*?)</p>"#, in: description).first.map(plainText) ?? plainText(description)
            var image = item["image"]
            if provider.style == .bbc { image = image?.replacingOccurrences(of: "/standard/240/", with: "/standard/976/") }
            return Story(source: provider.id, feed: feed.id, title: plainText(title), body: [summary], bullets: false,
                         date: rssDate(item["pubDate"]), category: section ?? "Nyheter",
                         imageURL: image.flatMap(URL.init(string:)), link: articleURL(item))
        }
    }

    // MARK: - Helpers

    /// RSS <link> text or Atom <link href>; SCB's feed still says http, so upgrade to https.
    private static func articleURL(_ item: [String: String]) -> URL? {
        guard var link = item["link"] ?? item["guid"], link.hasPrefix("http") else { return nil }
        if link.hasPrefix("http://") { link = "https://" + link.dropFirst(7) }
        return URL(string: link)
    }

    private static func titleKey(_ title: String) -> String {
        title.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func pathParts(_ link: String?) -> [String] {
        (URL(string: link ?? "")?.pathComponents ?? []).filter { $0 != "/" }
    }

    private static func rssDate(_ s: String?) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz"] {
            f.dateFormat = format
            if let s, let date = f.date(from: s) { return date }
        }
        return .distantPast
    }

    private static func isoDate(_ s: String?) -> Date {
        s.flatMap(ISO8601DateFormatter().date(from:)) ?? .distantPast
    }

    private static func captures(_ pattern: String, in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    private static func plainText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, char) in ["&nbsp;": " ", "&quot;": "\"", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&amp;": "&"] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Flattens RSS <item> and Atom <entry> elements into dictionaries of child text.
private final class FeedParser: NSObject, XMLParserDelegate {
    private var items: [[String: String]] = []
    private var current: [String: String]?
    private var text = ""

    static func items(in data: Data) -> [[String: String]] {
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items.filter { !($0["title"] ?? "").isEmpty }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if name == "item" || name == "entry" {
            current = [:]
        } else if current != nil {
            if name == "link", let href = attributes["href"] { current?["link"] = href }
            if name == "category", let term = attributes["term"], !term.isEmpty { current?["category"] = term }
            if ["media:content", "media:thumbnail", "enclosure"].contains(name), let url = attributes["url"], current?["image"] == nil {
                current?["image"] = url
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(decoding: block, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "item" || name == "entry" {
            if let current { items.append(current) }
            current = nil
        } else if current != nil, current?[name] == nil {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { current?[name] = value }
        }
        text = ""
    }
}
