import Foundation

/// Localisation using the standard Apple format: one `<code>.lproj/Localizable.strings`
/// per language in Resources/, English text as keys. Translators only edit those files.
///
/// Lookup is done explicitly (not via NSLocalizedString) so the app and the screen saver
/// can follow the language chosen in the app, not just the system's.
enum L10n {
    struct Language: Identifiable {
        let code: String       // .lproj folder name / locale identifier
        let flag: String
        let name: String       // in its own language
        var rightToLeft = false
        var id: String { code }
    }

    /// English and Swedish, the ten most spoken languages in the world, and five more of Europe's largest.
    static let languages: [Language] = [
        Language(code: "en", flag: "🇬🇧", name: "English"),
        Language(code: "sv", flag: "🇸🇪", name: "Svenska"),
        Language(code: "zh-Hans", flag: "🇨🇳", name: "简体中文"),
        Language(code: "hi", flag: "🇮🇳", name: "हिन्दी"),
        Language(code: "es", flag: "🇪🇸", name: "Español"),
        Language(code: "ar", flag: "🇸🇦", name: "العربية", rightToLeft: true),
        Language(code: "fr", flag: "🇫🇷", name: "Français"),
        Language(code: "bn", flag: "🇧🇩", name: "বাংলা"),
        Language(code: "pt", flag: "🇵🇹", name: "Português"),
        Language(code: "ru", flag: "🇷🇺", name: "Русский"),
        Language(code: "id", flag: "🇮🇩", name: "Bahasa Indonesia"),
        Language(code: "ur", flag: "🇵🇰", name: "اردو", rightToLeft: true),
        Language(code: "de", flag: "🇩🇪", name: "Deutsch"),
        Language(code: "it", flag: "🇮🇹", name: "Italiano"),
        Language(code: "pl", flag: "🇵🇱", name: "Polski"),
        Language(code: "uk", flag: "🇺🇦", name: "Українська"),
        Language(code: "nl", flag: "🇳🇱", name: "Nederlands"),
    ]

    /// Language chosen in the app; nil follows the system.
    static var override: String?

    /// The language in use: the chosen one, else the best match for the system's preferred languages.
    static var code: String {
        if let override, languages.contains(where: { $0.code == override }) { return override }
        return Bundle.preferredLocalizations(from: languages.map(\.code), forPreferences: Locale.preferredLanguages).first ?? "en"
    }

    static var current: Language { languages.first { $0.code == code } ?? languages[0] }
    static var locale: Locale { Locale(identifier: code) }

    /// Letter spacing breaks up connected scripts (Arabic, Urdu, Devanagari, Bengali) and suits Chinese poorly.
    static var allowsTracking: Bool { !["ar", "ur", "hi", "bn", "zh-Hans"].contains(code) }

    private static var tables: [String: Bundle] = [:]
    private static let missing = "\u{1}missing"

    private static func table(_ code: String) -> Bundle? {
        if let cached = tables[code] { return cached }
        guard let path = Bundle(for: BundleToken.self).path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        tables[code] = bundle
        return bundle
    }

    /// Looks a key up in a table ("Localizable" by default, "Help" for the help page), falling back to English.
    static func string(_ key: String, table name: String? = nil) -> String {
        for code in [code, "en"] {
            if let value = table(code)?.localizedString(forKey: key, value: missing, table: name), value != missing { return value }
        }
        return key
    }

    /// Help page text (Help.strings), Markdown.
    static func help(_ key: String) -> String { string(key, table: "Help") }
}

/// Translates an English key, optionally filling in printf-style arguments (%@, %d).
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = L10n.string(key)
    return args.isEmpty ? format : String(format: format, locale: L10n.locale, arguments: args)
}

private final class BundleToken {}
