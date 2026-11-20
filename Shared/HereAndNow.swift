import Foundation

/// A place for the "Here and now" card: weather point, county (for SMHI's warnings) and
/// electricity price area.
struct LocalPlace: Codable, Equatable, Hashable, Identifiable {
    var name: String
    var latitude: Double
    var longitude: Double
    var county: String          // as SMHI names it, e.g. "Stockholms län"
    var priceArea: String       // "SE1" … "SE4"
    var id: String { "\(name)|\(latitude)|\(longitude)" }

    static let priceAreas = ["SE1", "SE2", "SE3", "SE4"]

    static let counties = ["Blekinge län", "Dalarnas län", "Gotlands län", "Gävleborgs län", "Hallands län", "Jämtlands län",
                           "Jönköpings län", "Kalmar län", "Kronobergs län", "Norrbottens län", "Skåne län", "Stockholms län",
                           "Södermanlands län", "Uppsala län", "Värmlands län", "Västerbottens län", "Västernorrlands län",
                           "Västmanlands län", "Västra Götalands län", "Örebro län", "Östergötlands län"]

    static let presets: [LocalPlace] = [
        .init(name: "Stockholm", latitude: 59.3293, longitude: 18.0686, county: "Stockholms län", priceArea: "SE3"),
        .init(name: "Göteborg", latitude: 57.7089, longitude: 11.9746, county: "Västra Götalands län", priceArea: "SE3"),
        .init(name: "Malmö", latitude: 55.6050, longitude: 13.0038, county: "Skåne län", priceArea: "SE4"),
        .init(name: "Uppsala", latitude: 59.8586, longitude: 17.6389, county: "Uppsala län", priceArea: "SE3"),
        .init(name: "Västerås", latitude: 59.6099, longitude: 16.5448, county: "Västmanlands län", priceArea: "SE3"),
        .init(name: "Örebro", latitude: 59.2753, longitude: 15.2134, county: "Örebro län", priceArea: "SE3"),
        .init(name: "Linköping", latitude: 58.4108, longitude: 15.6214, county: "Östergötlands län", priceArea: "SE3"),
        .init(name: "Helsingborg", latitude: 56.0465, longitude: 12.6945, county: "Skåne län", priceArea: "SE4"),
        .init(name: "Jönköping", latitude: 57.7826, longitude: 14.1618, county: "Jönköpings län", priceArea: "SE3"),
        .init(name: "Norrköping", latitude: 58.5877, longitude: 16.1924, county: "Östergötlands län", priceArea: "SE3"),
        .init(name: "Lund", latitude: 55.7047, longitude: 13.1910, county: "Skåne län", priceArea: "SE4"),
        .init(name: "Umeå", latitude: 63.8258, longitude: 20.2630, county: "Västerbottens län", priceArea: "SE2"),
        .init(name: "Gävle", latitude: 60.6749, longitude: 17.1413, county: "Gävleborgs län", priceArea: "SE3"),
        .init(name: "Borås", latitude: 57.7210, longitude: 12.9401, county: "Västra Götalands län", priceArea: "SE3"),
        .init(name: "Södertälje", latitude: 59.1955, longitude: 17.6253, county: "Stockholms län", priceArea: "SE3"),
        .init(name: "Eskilstuna", latitude: 59.3666, longitude: 16.5077, county: "Södermanlands län", priceArea: "SE3"),
        .init(name: "Halmstad", latitude: 56.6745, longitude: 12.8578, county: "Hallands län", priceArea: "SE4"),
        .init(name: "Växjö", latitude: 56.8777, longitude: 14.8091, county: "Kronobergs län", priceArea: "SE4"),
        .init(name: "Karlstad", latitude: 59.4022, longitude: 13.5115, county: "Värmlands län", priceArea: "SE3"),
        .init(name: "Sundsvall", latitude: 62.3908, longitude: 17.3069, county: "Västernorrlands län", priceArea: "SE2"),
        .init(name: "Östersund", latitude: 63.1792, longitude: 14.6357, county: "Jämtlands län", priceArea: "SE2"),
        .init(name: "Luleå", latitude: 65.5848, longitude: 22.1567, county: "Norrbottens län", priceArea: "SE1"),
        .init(name: "Kiruna", latitude: 67.8558, longitude: 20.2253, county: "Norrbottens län", priceArea: "SE1"),
        .init(name: "Kalmar", latitude: 56.6634, longitude: 16.3568, county: "Kalmar län", priceArea: "SE4"),
        .init(name: "Karlskrona", latitude: 56.1612, longitude: 15.5869, county: "Blekinge län", priceArea: "SE4"),
        .init(name: "Kristianstad", latitude: 56.0294, longitude: 14.1567, county: "Skåne län", priceArea: "SE4"),
        .init(name: "Visby", latitude: 57.6348, longitude: 18.2948, county: "Gotlands län", priceArea: "SE3"),
        .init(name: "Falun", latitude: 60.6065, longitude: 15.6355, county: "Dalarnas län", priceArea: "SE3"),
        .init(name: "Nyköping", latitude: 58.7530, longitude: 17.0079, county: "Södermanlands län", priceArea: "SE3"),
        .init(name: "Varberg", latitude: 57.1056, longitude: 12.2508, county: "Hallands län", priceArea: "SE3"),
        .init(name: "Trollhättan", latitude: 58.2837, longitude: 12.2886, county: "Västra Götalands län", priceArea: "SE3"),
        .init(name: "Skövde", latitude: 58.3903, longitude: 13.8461, county: "Västra Götalands län", priceArea: "SE3"),
        .init(name: "Örnsköldsvik", latitude: 63.2909, longitude: 18.7153, county: "Västernorrlands län", priceArea: "SE2"),
        .init(name: "Ystad", latitude: 55.4295, longitude: 13.8200, county: "Skåne län", priceArea: "SE4"),
    ].sorted { $0.name.compare($1.name, locale: Locale(identifier: "sv_SE")) == .orderedAscending }
}

/// What the "Here and now" card shows. Every part comes from an open service that needs no key:
/// SMHI (weather and warnings), elprisetjustnu.se (spot price), the Riksbank (policy rate) and SCB (inflation).
struct LocalReport {
    struct Weather {
        let place: String
        let temperature: Double
        let symbol: Int          // SMHI weather symbol, 1–27
        let wind: Double         // m/s
        let low: Double          // next 12 hours
        let high: Double
    }

    struct Warning {
        let level: String        // MESSAGE, YELLOW, ORANGE, RED
        let levelName: String
        let event: String
        let area: String
        var severity: Int { ["MESSAGE": 0, "YELLOW": 1, "ORANGE": 2, "RED": 3][level] ?? 0 }
    }

    struct Power {
        let area: String
        let now: Double          // öre/kWh, spot price without VAT and fees
        let low: Double
        let high: Double
        let cheapestHour: Date?  // start of the cheapest whole hour still to come today
    }

    var weather: [Weather] = []
    var warnings: [Warning] = []
    var warningsChecked = false
    var power: Power?
    var policyRate: (value: Double, date: Date)?
    var inflation: (value: Double, month: Date)?

    var isEmpty: Bool { weather.isEmpty && !warningsChecked && power == nil && policyRate == nil && inflation == nil }
}

enum HereAndNow {
    /// Parts of the card that can be switched off.
    static let partIDs = ["weather", "warnings", "power", "rate", "inflation"]

    /// The price area in use: the user's choice, else the first place's.
    static func priceArea(_ s: NyheterSettings) -> String? { s.priceArea ?? s.places.first?.priceArea }

    /// Fetches every part the user wants; calls back once, on the main queue.
    static func fetch(_ s: NyheterSettings, now: Date = Date(), completion: @escaping (LocalReport) -> Void) {
        var report = LocalReport()
        let group = DispatchGroup()
        let parts = Set(s.localParts)
        let places = Array(s.places.prefix(NyheterSettings.maxPlaces))

        if parts.contains("weather") {
            for place in places {
                group.enter()
                let url = URL(string: String(format: "https://opendata-download-metfcst.smhi.se/api/category/snow1g/version/1/geotype/point/lon/%.4f/lat/%.4f/data.json",
                                             place.longitude, place.latitude))!
                WebCache.get(url, maxAge: 30 * 60) { data in
                    if let data, let weather = parseWeather(data, place: place.name, now: now) { report.weather.append(weather) }
                    group.leave()
                }
            }
        }
        if parts.contains("warnings"), !places.isEmpty {
            group.enter()
            WebCache.get(URL(string: "https://opendata-download-warnings.smhi.se/ibww/api/version/1/warning.json")!, maxAge: 15 * 60) { data in
                if let data, let warnings = parseWarnings(data, counties: Set(places.map(\.county))) {
                    report.warnings = warnings
                    report.warningsChecked = true
                }
                group.leave()
            }
        }
        if parts.contains("power"), let area = priceArea(s) {
            group.enter()
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
            let day = calendar.dateComponents([.year, .month, .day], from: now)
            let url = URL(string: String(format: "https://www.elprisetjustnu.se/api/v1/prices/%04d/%02d-%02d_%@.json", day.year!, day.month!, day.day!, area))!
            WebCache.get(url, maxAge: 6 * 3600) { data in
                if let data { report.power = parsePower(data, area: area, now: now) }
                group.leave()
            }
        }
        if parts.contains("rate") {
            group.enter()
            WebCache.get(URL(string: "https://api.riksbank.se/swea/v1/Observations/Latest/SECBREPOEFF")!, maxAge: 6 * 3600) { data in
                if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let value = (json["value"] as? NSNumber)?.doubleValue, let date = (json["date"] as? String).flatMap(day) {
                    report.policyRate = (value, date)
                }
                group.leave()
            }
        }
        if parts.contains("inflation") {
            group.enter()
            let url = URL(string: "https://statistikdatabasen.scb.se/api/v2/tables/TAB6590/data?lang=en&valuecodes%5BContentsCode%5D=000007ZM&valuecodes%5BTid%5D=top(1)&outputFormat=json-stat2")!
            WebCache.get(url, maxAge: 12 * 3600) { data in
                if let data { report.inflation = parseInflation(data) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            // Keep the user's order of places.
            report.weather.sort { a, b in
                (places.firstIndex { $0.name == a.place } ?? 0) < (places.firstIndex { $0.name == b.place } ?? 0)
            }
            completion(report)
        }
    }

    // MARK: - Parsers

    private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()

    private static func day(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Stockholm")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    static func parseWeather(_ data: Data, place: String, now: Date) -> LocalReport.Weather? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let series = json["timeSeries"] as? [[String: Any]] else { return nil }
        let points: [(date: Date, values: [String: Any])] = series.compactMap { entry in
            guard let time = (entry["time"] as? String).flatMap(iso.date), let values = entry["data"] as? [String: Any] else { return nil }
            return (time, values)
        }
        // The forecast for the hour that is under way, then the next twelve hours.
        guard let start = points.firstIndex(where: { $0.date > now.addingTimeInterval(-3600) }) else { return nil }
        let next = points[start...].prefix(12)
        func number(_ values: [String: Any], _ key: String) -> Double? { (values[key] as? NSNumber)?.doubleValue }
        guard let current = next.first, let temperature = number(current.values, "air_temperature") else { return nil }
        let temperatures = next.compactMap { number($0.values, "air_temperature") }
        return .init(place: place, temperature: temperature, symbol: Int(number(current.values, "symbol_code") ?? 0),
                     wind: number(current.values, "wind_speed") ?? 0,
                     low: temperatures.min() ?? temperature, high: temperatures.max() ?? temperature)
    }

    static func parseWarnings(_ data: Data, counties: Set<String>) -> [LocalReport.Warning]? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let swedish = L10n.code == "sv"
        func text(_ value: Any?) -> String? {
            guard let dict = value as? [String: Any] else { return nil }
            return (swedish ? dict["sv"] : dict["en"] ?? dict["sv"]) as? String
        }
        var out: [LocalReport.Warning] = []
        for warning in list {
            let event = text(warning["event"]) ?? ""
            for area in warning["warningAreas"] as? [[String: Any]] ?? [] {
                let affected = (area["affectedAreas"] as? [[String: Any]] ?? []).compactMap { $0["sv"] as? String }
                guard let county = affected.first(where: counties.contains) else { continue }
                let level = area["warningLevel"] as? [String: Any]
                let name = affected.count == 1 ? (text(area["areaName"]) ?? county) : county
                out.append(.init(level: level?["code"] as? String ?? "MESSAGE", levelName: text(level) ?? "",
                                 event: text(area["eventDescription"]) ?? event, area: name))
            }
        }
        // Most severe first; the same event in the same area once.
        var seen = Set<String>()
        return out.sorted { $0.severity > $1.severity }.filter { seen.insert($0.event + $0.area).inserted }
    }

    static func parsePower(_ data: Data, area: String, now: Date) -> LocalReport.Power? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let f = ISO8601DateFormatter()
        let slots: [(start: Date, end: Date, ore: Double)] = list.compactMap { item in
            guard let start = (item["time_start"] as? String).flatMap(f.date), let end = (item["time_end"] as? String).flatMap(f.date),
                  let sek = (item["SEK_per_kWh"] as? NSNumber)?.doubleValue else { return nil }
            return (start, end, sek * 100)
        }
        guard let current = slots.first(where: { $0.start <= now && now < $0.end }) else { return nil }
        // Whole hours (prices may come in quarters), from the hour under way.
        var hours: [Date: [Double]] = [:]
        let calendar = Calendar.current
        for slot in slots {
            let hour = calendar.dateInterval(of: .hour, for: slot.start)!.start
            hours[hour, default: []].append(slot.ore)
        }
        let thisHour = calendar.dateInterval(of: .hour, for: now)!.start
        let cheapest = hours.filter { $0.key >= thisHour }.min { a, b in
            a.value.reduce(0, +) / Double(a.value.count) < b.value.reduce(0, +) / Double(b.value.count)
        }?.key
        return .init(area: area, now: current.ore, low: slots.map(\.ore).min()!, high: slots.map(\.ore).max()!, cheapestHour: cheapest)
    }

    static func parseInflation(_ data: Data) -> (value: Double, month: Date)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = (json["value"] as? [Any])?.first.flatMap({ ($0 as? NSNumber)?.doubleValue }),
              let time = ((json["dimension"] as? [String: Any])?["Tid"] as? [String: Any])?["category"] as? [String: Any],
              let period = (time["index"] as? [String: Any])?.keys.first else { return nil }
        // "2026M10" → 1 October 2026.
        let parts = period.split(separator: "M")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
              let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
        return (value, date)
    }

    /// SMHI's weather symbol as a word (English key for L()) and a Lucide icon.
    static func describe(symbol: Int) -> (text: String, icon: String) {
        switch symbol {
        case 1, 2: return ("Clear sky", "sun")
        case 3, 4: return ("Partly cloudy", "cloud-sun")
        case 5, 6: return ("Cloudy", "cloud")
        case 7: return ("Fog", "cloud-fog")
        case 8, 18: return ("Light rain", "cloud-drizzle")
        case 9, 10, 19, 20: return ("Rain", "cloud-rain")
        case 11, 21: return ("Thunder", "cloud-lightning")
        case 12, 13, 14, 22, 23, 24: return ("Sleet", "cloud-hail")
        case 15, 16, 17, 25, 26, 27: return ("Snow", "cloud-snow")
        default: return ("", "thermometer")
        }
    }
}
