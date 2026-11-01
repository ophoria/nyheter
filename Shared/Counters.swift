import Foundation

/// A live counter extrapolated from a published yearly figure, the same way
/// Worldometers' counters work. Values are estimates, not measurements.
struct WorldCounter: Identifiable {
    enum Kind {
        case total(base: Double, at: Date, perYear: Double)
        case thisYear(perYear: Double)
        case today(perYear: Double)
    }

    let id: String
    let label: String
    let kind: Kind
    let source: String
    /// Country the number is about (shown only when a source from there is in use); nil = the world.
    var country: String? = nil

    static let defaultIDs = ["population", "births_today", "deaths_today", "growth_today", "co2_year", "sweden_population"]

    static let all: [WorldCounter] = [
        WorldCounter(id: "population", label: "World population",
                     kind: .total(base: 8_231_613_070, at: date("2025-07-01"), perYear: 70_000_000), source: "UN, WPP 2024"),
        WorldCounter(id: "births_today", label: "Births in the world today", kind: .today(perYear: 132_000_000), source: "UN, WPP 2024"),
        WorldCounter(id: "births_year", label: "Births in the world this year", kind: .thisYear(perYear: 132_000_000), source: "UN, WPP 2024"),
        WorldCounter(id: "deaths_today", label: "Deaths in the world today", kind: .today(perYear: 62_000_000), source: "UN, WPP 2024"),
        WorldCounter(id: "deaths_year", label: "Deaths in the world this year", kind: .thisYear(perYear: 62_000_000), source: "UN, WPP 2024"),
        WorldCounter(id: "growth_today", label: "Population growth today", kind: .today(perYear: 70_000_000), source: "UN, WPP 2024"),
        WorldCounter(id: "co2_year", label: "CO₂ emissions this year (tonnes)", kind: .thisYear(perYear: 38_100_000_000), source: "Global Carbon Project"),
        WorldCounter(id: "forest_year", label: "Tropical primary forest lost this year (ha)", kind: .thisYear(perYear: 6_700_000), source: "Global Forest Watch"),
        WorldCounter(id: "internet_users", label: "Internet users",
                     kind: .total(base: 6_000_000_000, at: date("2025-07-01"), perYear: 200_000_000), source: "ITU"),
        WorldCounter(id: "sweden_population", label: "Population of Sweden",
                     kind: .total(base: 10_587_710, at: date("2024-12-31"), perYear: 25_000), source: "SCB", country: "SE"),
        WorldCounter(id: "sweden_births_today", label: "Births in Sweden today", kind: .today(perYear: 98_000), source: "SCB", country: "SE"),
    ]

    func isRelevant(to settings: NyheterSettings) -> Bool {
        country.map { c in settings.enabledProviders.contains { $0.country == c } } ?? true
    }

    func value(at now: Date = Date()) -> Double {
        let calendar = Calendar.current
        switch kind {
        case let .total(base, at, perYear):
            return base + perYear * now.timeIntervalSince(at) / Self.secondsPerYear
        case let .thisYear(perYear):
            let start = calendar.date(from: calendar.dateComponents([.year], from: now))!
            return perYear * now.timeIntervalSince(start) / Self.secondsPerYear
        case let .today(perYear):
            return perYear * now.timeIntervalSince(calendar.startOfDay(for: now)) / Self.secondsPerYear
        }
    }

    private static let secondsPerYear = 365.2425 * 86_400

    private static func date(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s + "T00:00:00Z")!
    }

    /// Number formatter in the app's language (digit grouping differs between languages).
    static var formatter: NumberFormatter {
        if cachedFormatter.locale.identifier != L10n.locale.identifier {
            cachedFormatter = NumberFormatter()
            cachedFormatter.numberStyle = .decimal
            cachedFormatter.locale = L10n.locale
            cachedFormatter.maximumFractionDigits = 0
        }
        return cachedFormatter
    }
    private static var cachedFormatter = NumberFormatter()
}
