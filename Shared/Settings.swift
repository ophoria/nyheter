import Foundation

/// Everything the user can change. The app writes it as JSON; the screen
/// saver reads the same file (its sandbox allows reading any path).
struct NyheterSettings: Codable, Equatable {
    // Timing
    var fixedSeconds: Double = 15
    var adaptive = false
    var baseSeconds: Double = 4
    var secondsPerWord: Double = 0.3
    var minSeconds: Double = 8
    var maxSeconds: Double = 30
    // Separate formula for the "headlines only" layout, where texts are short.
    var headlineBaseSeconds: Double = 2
    var headlineSecondsPerWord: Double = 0.6
    var headlineMinSeconds: Double = 4
    var headlineMaxSeconds: Double = 12

    // Sources, per provider id (see Sources.providers). A provider that is switched off keeps
    // its settings here, so they come back when it is switched on again.
    var sources: [String: SourceSettings] = [:]

    // World counters
    var counters = true
    var counterEvery = 6
    var counterSeconds: Double = 15
    var counterIDs: [String] = WorldCounter.defaultIDs

    // Order
    var orderMode = OrderMode.turns
    var turnPattern: [String] = Sources.providerIDs     // may repeat a source, e.g. SVT, SVT, SR
    var blockOrder: [String] = Sources.providerIDs
    var maxPerSource = 25
    var refreshMinutes = 30                            // one of refreshChoices

    var themeID = Theme.all[0].id
    var language: String?                              // nil = follow macOS
    var randomTheme = false                            // pick a new theme for every story…
    var randomThemeIDs: [String] = Theme.all.map(\.id)  // …from these

    // Layout
    var showUpcoming = true        // right-hand column with the next stories
    var headlineOnly = false       // hide the intro text / bullet points
    var showProgress = true        // progress line and position counter at the bottom

    // Filters
    var filters: [NewsFilter] = [NewsFilter.dateRoundups, NewsFilter.entertainment]
    var blockedSections: [String] = []      // e.g. "Kultur", "Sport" — matched against each story's section
    var logClearedAt: Date?        // log entries before this are hidden (the saver's own file can't be cleared from the app)

    enum OrderMode: String, Codable, CaseIterable {
        case turns, blocks, random
    }

    static let maxStories = 100
    static let refreshChoices = [30, 60, 120, 180, 360, 720, 1440]
    static let refreshRange = 30...1440

    /// A provider's settings, or its defaults if the user has never touched it.
    func source(_ id: String) -> SourceSettings {
        sources[id] ?? SourceSettings(enabled: Sources.provider(id)?.defaultEnabled ?? false)
    }

    mutating func updateSource(_ id: String, _ change: (inout SourceSettings) -> Void) {
        var config = source(id)
        change(&config)
        sources[id] = config
    }

    /// Whether a provider is in use ("world" is the counter slide).
    func isEnabled(_ id: String) -> Bool {
        id == "world" ? counters : source(id).enabled && Sources.provider(id) != nil
    }

    func isOn(_ feed: Provider.Feed, of provider: Provider) -> Bool {
        source(provider.id).feeds[feed.id] ?? feed.defaultOn
    }

    var enabledProviders: [Provider] { Sources.providers.filter { isEnabled($0.id) } }

    /// Adds sources in use that the turn order or block order doesn't mention yet, so the
    /// Order tab always lists every active source. Sources switched off keep their place.
    mutating func includeActiveSources() {
        for provider in enabledProviders {
            if !turnPattern.contains(provider.id) { turnPattern.append(provider.id) }
            if !blockOrder.contains(provider.id) { blockOrder.append(provider.id) }
        }
    }

    /// Languages of the providers in use, e.g. ["sv", "en"].
    var sourceLanguages: Set<String> { Set(enabledProviders.map(\.language)) }

    /// How long a story stays on screen, given the number of words actually shown.
    func duration(words: Int, headlineOnly: Bool) -> Double {
        guard adaptive else { return fixedSeconds }
        let f = headlineOnly
            ? (base: headlineBaseSeconds, perWord: headlineSecondsPerWord, min: headlineMinSeconds, max: headlineMaxSeconds)
            : (base: baseSeconds, perWord: secondsPerWord, min: minSeconds, max: maxSeconds)
        return min(f.max, max(f.min, f.base + f.perWord * Double(words)))
    }

    /// Signature of everything that affects which feeds are fetched.
    var sourceSignature: String {
        Sources.requests(for: self).map(\.url.absoluteString).joined(separator: " ")
    }

    /// Signature of everything that only changes how fetched stories are picked and ordered.
    var orderSignature: String {
        "\(sources)\(orderMode)\(turnPattern)\(blockOrder)\(maxPerSource)\(filters)\(blockedSections)"
    }

    // MARK: - Persistence

    /// The real home folder, also from inside the screen saver's sandbox container.
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var fileURL: URL {
        realHome.appendingPathComponent("Library/Application Support/Nyheter/settings.json")
    }

    /// Loads saved settings, filling any keys missing from older files with defaults.
    static func load() -> NyheterSettings {
        guard let data = try? Data(contentsOf: fileURL),
              var saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaults = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(NyheterSettings())) as? [String: Any]
        else { return NyheterSettings() }
        if saved["sources"] == nil { saved["sources"] = migratedSources(saved) }
        guard let merged = try? JSONSerialization.data(withJSONObject: defaults.merging(saved) { _, new in new }),
              var settings = try? JSONDecoder().decode(NyheterSettings.self, from: merged)
        else { return NyheterSettings() }
        // Older versions offered updates every 10 or 15 minutes.
        settings.refreshMinutes = refreshChoices.first { $0 >= settings.refreshMinutes } ?? refreshRange.upperBound
        // The built-in filters target Swedish words; older files didn't say so.
        for i in settings.filters.indices where settings.filters[i].language == nil
            && [NewsFilter.dateRoundups.pattern, NewsFilter.entertainment.pattern].contains(settings.filters[i].pattern) {
            settings.filters[i].language = "sv"
        }
        return settings
    }

    /// Settings files from before per-provider sources had one flat key per option.
    private static func migratedSources(_ old: [String: Any]) -> [String: Any] {
        func flag(_ key: String, _ fallback: Bool) -> Bool { old[key] as? Bool ?? fallback }
        let svt = [("svt-top", flag("svtTop", true)), ("svt-inrikes", flag("svtDomestic", false)),
                   ("svt-utrikes", flag("svtWorld", false)), (Sources.svtLocalFeed, flag("svtLocal", true))]
        let dn = [("dn-top", flag("dnTop", false)), ("dn-sverige", flag("dnSweden", false)), ("dn-varlden", flag("dnWorld", false))]
        func entry(_ feeds: [(String, Bool)], enabled: Bool, extra: [String: Any] = [:]) -> [String: Any] {
            var feedMap = Dictionary(uniqueKeysWithValues: feeds)
            if !enabled, let first = feeds.first { feedMap[first.0] = true }   // remember a sensible default for later
            return ["enabled": enabled, "feeds": feedMap].merging(extra) { a, _ in a }
        }
        return [
            "svt": entry(svt, enabled: svt.contains { $0.1 }, extra: ["regions": old["svtRegions"] as? [String] ?? [], "maxLocal": old["maxLocal"] as? Int ?? 4]),
            "sr": entry([("sr-ekot", true)], enabled: flag("srEkot", true)),
            "dn": entry(dn, enabled: dn.contains { $0.1 }),
            "scb": entry([("scb", true)], enabled: flag("scb", false), extra: ["maxItems": old["maxSCB"] as? Int ?? 3]),
        ]
    }

    func save() {
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(self).write(to: url, options: .atomic)
    }

    static var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }
}

/// Settings for one provider. Kept when the provider is switched off.
struct SourceSettings: Codable, Equatable {
    var enabled: Bool
    var feeds: [String: Bool] = [:]     // feed id → on; missing = the feed's default
    var regions: [String] = []          // SVT: regions for local news; empty = any region from the top feed
    var maxLocal = 4                    // SVT: cap on regional stories
    var maxItems = 3                    // SCB: cap on items

    init(enabled: Bool) { self.enabled = enabled }

    /// Missing keys (older files, migrated settings) fall back to the defaults above.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        feeds = try c.decodeIfPresent([String: Bool].self, forKey: .feeds) ?? [:]
        regions = try c.decodeIfPresent([String].self, forKey: .regions) ?? []
        maxLocal = try c.decodeIfPresent(Int.self, forKey: .maxLocal) ?? 4
        maxItems = try c.decodeIfPresent(Int.self, forKey: .maxItems) ?? 3
    }
}
