import Foundation

/// A day in history, from Wikipedia's "On this day" (Wikimedia's feed API, no key needed).
struct WikiEvent {
    let year: Int
    let text: String
    let link: URL?
}

enum OnThisDay {
    /// Wikipedias that publish a curated "On this day" list in the feed API (checked November 2026).
    static let languages = ["ar", "bs", "cs", "de", "en", "es", "fr", "it", "pt", "ru", "sv", "tr", "uk", "zh"]

    /// The Wikipedia in use: the user's choice, else the app's language when that Wikipedia has the list, else English.
    static func language(_ s: NyheterSettings) -> String {
        if let chosen = s.onThisDayLanguage, languages.contains(chosen) { return chosen }
        let app = String(L10n.code.prefix(2))
        return languages.contains(app) ? app : "en"
    }

    /// A language's name in its own language, e.g. "svenska".
    static func nativeName(_ code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code).map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? code
    }

    static func fetch(language: String, date: Date = Date(), completion: @escaping ([WikiEvent]) -> Void) {
        let day = Calendar.current.dateComponents([.month, .day], from: date)
        let url = URL(string: String(format: "https://api.wikimedia.org/feed/v1/wikipedia/%@/onthisday/selected/%02d/%02d", language, day.month!, day.day!))!
        // One request per language and day is plenty; the address names the day.
        WebCache.get(url, maxAge: 7 * 86400) { data in
            completion(data.map(parse) ?? [])
        }
    }

    static func parse(_ data: Data) -> [WikiEvent] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let selected = json["selected"] as? [[String: Any]] else { return [] }
        return selected.compactMap { item in
            guard let text = item["text"] as? String, let year = (item["year"] as? NSNumber)?.intValue else { return nil }
            let page = (item["pages"] as? [[String: Any]])?.first
            let link = (((page?["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String).flatMap(URL.init(string:))
            return WikiEvent(year: year, text: Sources.plainText(text), link: link)
        }
    }
}
