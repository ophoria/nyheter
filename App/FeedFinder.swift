import Foundation
import NaturalLanguage

/// Turns what the user pastes (a feed address, or a website that links to its feed) into a CustomFeed.
enum FeedFinder {
    enum Failure: Error {
        case unreachable, noFeed

        var message: String {
            switch self {
            case .unreachable: return L("Couldn't reach that address.")
            case .noFeed: return L("No news feed found at that address.")
            }
        }
    }

    static func find(_ text: String) async throws -> CustomFeed {
        var address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.contains("://") { address = "https://" + address }
        guard let url = URL(string: address), url.host != nil else { throw Failure.noFeed }
        let (data, final) = try await fetch(url)
        if let feed = feed(data, at: url) { return feed }
        // A web page: try the feeds it announces in <link rel="alternate" …>.
        for candidate in alternates(in: String(decoding: data, as: UTF8.self), base: final) {
            if let (data, _) = try? await fetch(candidate), let feed = feed(data, at: candidate) { return feed }
        }
        throw Failure.noFeed
    }

    private static func fetch(_ url: URL) async throws -> (Data, URL) {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Nyheter/1.0 (macOS screen saver)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { throw Failure.unreachable }
        return (data, response.url ?? url)
    }

    private static func feed(_ data: Data, at url: URL) -> CustomFeed? {
        let parsed = FeedParser.parse(data)
        guard !parsed.items.isEmpty else { return nil }
        let host = url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? url.absoluteString
        let name = parsed.title.flatMap { $0.isEmpty ? nil : $0 } ?? host
        return CustomFeed(name: name, url: url.absoluteString, language: language(of: parsed.items.compactMap { $0["title"] }))
    }

    /// The feed's language from its headlines, e.g. "sv" or "en".
    private static func language(of titles: [String]) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(titles.prefix(30).joined(separator: ". "))
        return recognizer.dominantLanguage?.rawValue.split(separator: "-").first.map(String.init) ?? "en"
    }

    private static func alternates(in html: String, base: URL) -> [URL] {
        guard let tag = try? NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: .caseInsensitive) else { return [] }
        let ns = html as NSString
        return tag.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let link = ns.substring(with: match.range)
            guard link.range(of: #"rel=["']?alternate"#, options: [.regularExpression, .caseInsensitive]) != nil,
                  link.range(of: #"type=["']?application/(rss|atom|feed)\+(xml|json)"#, options: [.regularExpression, .caseInsensitive]) != nil,
                  let href = link.range(of: #"(?<=href=["'])[^"']+"#, options: [.regularExpression, .caseInsensitive])
            else { return nil }
            return URL(string: String(link[href]).replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL
        }
    }
}
