import AppKit

struct FontSpec {
    enum Family { case serif, sans, mono, rounded }
    let family: Family
    let weight: NSFont.Weight
    var italic = false

    func font(_ size: CGFloat) -> NSFont {
        switch family {
        case .sans: return .systemFont(ofSize: size, weight: weight)
        case .mono: return .monospacedSystemFont(ofSize: size, weight: weight)
        case .serif, .rounded:
            var descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
            descriptor = descriptor.withDesign(family == .serif ? .serif : .rounded) ?? descriptor
            if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
            return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size)
        }
    }

    /// Same family with fixed-width digits, for ticking counters.
    func numberFont(_ size: CGFloat) -> NSFont {
        switch family {
        case .mono: return font(size)
        case .sans: return .monospacedDigitSystemFont(ofSize: size, weight: weight)
        case .serif, .rounded:
            let tabular: [NSFontDescriptor.FeatureKey: Int] = [.typeIdentifier: kNumberSpacingType, .selectorIdentifier: kMonospacedNumbersSelector]
            let descriptor = font(size).fontDescriptor.addingAttributes([.featureSettings: [tabular]])
            return NSFont(descriptor: descriptor, size: size) ?? font(size)
        }
    }
}

struct Theme {
    enum Chip { case filled, inverted, underline, highlight }

    let id: String
    let name: String
    let blurb: String
    let background: NSColor
    let text: NSColor
    let mutedAlpha: CGFloat
    let ruleAlpha: CGFloat
    let ledeAlpha: CGFloat
    let accents: [String: NSColor]
    /// Second, softer colour field per source; nil for no glow.
    let glows: [String: NSColor]?
    let glowAlpha: CGFloat
    /// The whole background takes the source colour.
    let flatBackground: Bool
    let chip: Chip
    let photo: Bool
    let scanlines: Bool
    let kickerRule: Bool
    let cursor: Bool
    let headline: FontSpec
    let headlineScale: CGFloat
    let headlineLineHeight: CGFloat
    let headlineKern: CGFloat
    let lede: FontSpec
    let ledeScale: CGFloat
    let ui: FontSpec
    let number: FontSpec
    /// Signal colour for chips, rules and the progress bar (Svea's yellow); nil uses the source colour.
    var highlight: NSColor? = nil
    /// Text colour on the highlight colour.
    var onHighlight: NSColor = .black
    /// Corner radius of the source chip as a fraction of its height (0.5 = pill).
    var chipRadius: CGFloat = 0
    /// A second colour field per source; without it the first field uses the source colour.
    var secondGlows: [String: NSColor]? = nil
    /// Soft glow around all text (Matrix).
    var textGlow = false
    /// Falling columns of glyphs behind the content (Matrix).
    var rain = false
    /// CRT screen look: rounded bezel, vignette and glass glare (Skyddsrum).
    var bezel = false
    /// A row of source tabs above the progress line, current source highlighted (Skyddsrum).
    var sourceTabs = false
    /// Occasional brightness flicker, like an old tube (Skyddsrum).
    var flicker = false
    var uppercaseHeadline = false
    /// The story photo shows through cut-outs: above the rule, in the side column and under the progress line.
    var photoCutouts = false
    /// Choosing the theme turns off the upcoming-stories column (its space goes to the photo).
    var hidesColumn = false

    var muted: NSColor { text.withAlphaComponent(mutedAlpha) }
    var rule: NSColor { text.withAlphaComponent(ruleAlpha) }

    func accent(_ source: String) -> NSColor { accents[source] ?? accents["default"] ?? text }
    /// Colour for labels and marks that sit on the background.
    func mark(_ source: String) -> NSColor { highlight ?? (flatBackground ? text : accent(source)) }
    func backdrop(_ source: String) -> NSColor { flatBackground ? accent(source) : background }

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? all[0] }

    static let all: [Theme] = [
        Theme(id: "morgon", name: "Morning Paper", blurb: "Light newsprint, black ink, rules and heavy serifs.",
              background: hex(0xf2ece0), text: hex(0x16140f), mutedAlpha: 0.6, ruleAlpha: 0.3, ledeAlpha: 0.85,
              accents: ["svt": hex(0xb3261e), "sr": hex(0x1f4e8c), "dn": hex(0x8a5d00), "scb": hex(0x1d6b4f), "world": hex(0x5b3c8c),
                       "nyt": hex(0x1a1a1a), "bbc": hex(0xb80000), "msnow": hex(0x2b3a8f)],
              glows: nil, glowAlpha: 0, flatBackground: false, chip: .underline, photo: false, scanlines: false, kickerRule: true, cursor: false,
              headline: FontSpec(family: .serif, weight: .black), headlineScale: 1, headlineLineHeight: 1.04, headlineKern: -0.015,
              lede: FontSpec(family: .serif, weight: .regular), ledeScale: 1,
              ui: FontSpec(family: .sans, weight: .bold), number: FontSpec(family: .serif, weight: .light)),

        Theme(id: "morgonbild", name: "Morning Paper Photo", blurb: "Morning Paper with the story’s photo above the rule, in the side column and under the progress line.",
              background: hex(0xf2ece0), text: hex(0x16140f), mutedAlpha: 0.6, ruleAlpha: 0.3, ledeAlpha: 0.85,
              accents: ["svt": hex(0xb3261e), "sr": hex(0x1f4e8c), "dn": hex(0x8a5d00), "scb": hex(0x1d6b4f), "world": hex(0x5b3c8c),
                       "nyt": hex(0x1a1a1a), "bbc": hex(0xb80000), "msnow": hex(0x2b3a8f)],
              glows: nil, glowAlpha: 0, flatBackground: false, chip: .underline, photo: false, scanlines: false, kickerRule: true, cursor: false,
              headline: FontSpec(family: .serif, weight: .black), headlineScale: 1, headlineLineHeight: 1.04, headlineKern: -0.015,
              lede: FontSpec(family: .serif, weight: .regular), ledeScale: 1,
              ui: FontSpec(family: .sans, weight: .bold), number: FontSpec(family: .serif, weight: .light),
              photoCutouts: true, hidesColumn: true),

        Theme(id: "natt", name: "Night Desk", blurb: "Dark and cinematic. Serif headlines, soft colour fields and toned press photos.",
              background: hex(0x0d0e11), text: hex(0xf3eee6), mutedAlpha: 0.55, ruleAlpha: 0.14, ledeAlpha: 0.82,
              accents: ["svt": hex(0xff6a4d), "sr": hex(0x5cc8ff), "dn": hex(0xf5c542), "scb": hex(0x4fe0b0), "world": hex(0xb48cff),
                       "nyt": hex(0xe9e4da), "bbc": hex(0xff5a5a), "msnow": hex(0x5d8bff)],
              glows: ["svt": hex(0x3a4dff), "sr": hex(0x7b3aff), "dn": hex(0xff7a3a), "scb": hex(0x1f6f8a), "world": hex(0x3a7bff),
                       "nyt": hex(0x4a4f63), "bbc": hex(0x8a1f1f), "msnow": hex(0x2a3f9a)],
              glowAlpha: 0.4, flatBackground: false, chip: .filled, photo: true, scanlines: false, kickerRule: false, cursor: false,
              headline: FontSpec(family: .serif, weight: .bold), headlineScale: 1, headlineLineHeight: 1.06, headlineKern: -0.02,
              lede: FontSpec(family: .serif, weight: .regular), ledeScale: 1,
              ui: FontSpec(family: .sans, weight: .semibold), number: FontSpec(family: .sans, weight: .ultraLight)),

        Theme(id: "svea", name: "Svea", blurb: "Blue and yellow. An even heavier sans serif, yellow blocks and big headlines.",
              background: hex(0x136a9b), text: hex(0xffffff), mutedAlpha: 0.78, ruleAlpha: 0.32, ledeAlpha: 0.95,
              accents: ["svt": hex(0x136a9b), "sr": hex(0x2284b9), "dn": hex(0x3d3d3d), "scb": hex(0x36a0ce), "world": hex(0x136a9b),
                       "nyt": hex(0x3d3d3d), "bbc": hex(0x2284b9), "msnow": hex(0x136a9b)],
              glows: nil, glowAlpha: 0, flatBackground: true, chip: .highlight, photo: false, scanlines: false, kickerRule: true, cursor: false,
              headline: FontSpec(family: .sans, weight: .black), headlineScale: 1.22, headlineLineHeight: 0.94, headlineKern: -0.045,
              lede: FontSpec(family: .sans, weight: .semibold), ledeScale: 0.98,
              ui: FontSpec(family: .sans, weight: .black), number: FontSpec(family: .sans, weight: .black),
              highlight: hex(0xfcc914), onHighlight: hex(0x3d3d3d)),

        Theme(id: "schweiz", name: "Swiss", blurb: "A solid colour per source, heavy sans serif and a strict grid.",
              background: hex(0x111111), text: hex(0xffffff), mutedAlpha: 0.72, ruleAlpha: 0.3, ledeAlpha: 0.92,
              accents: ["svt": hex(0xd9301f), "sr": hex(0x1d4ed8), "dn": hex(0x161616), "scb": hex(0x0a7a58), "world": hex(0x5b2bd6),
                       "nyt": hex(0x161616), "bbc": hex(0xb80000), "msnow": hex(0x0f3d7a)],
              glows: nil, glowAlpha: 0, flatBackground: true, chip: .inverted, photo: false, scanlines: false, kickerRule: false, cursor: false,
              headline: FontSpec(family: .sans, weight: .black), headlineScale: 1.12, headlineLineHeight: 0.98, headlineKern: -0.035,
              lede: FontSpec(family: .sans, weight: .medium), ledeScale: 0.95,
              ui: FontSpec(family: .sans, weight: .heavy), number: FontSpec(family: .sans, weight: .black)),

        Theme(id: "pastel", name: "Pastel", blurb: "Soft drifting pastel fields, rounded heavy letters and pills.",
              background: hex(0xffd6c9), text: hex(0x3b2a4a), mutedAlpha: 0.62, ruleAlpha: 0.22, ledeAlpha: 0.88,
              accents: ["svt": hex(0xffd6c9), "sr": hex(0xc9f0e4), "dn": hex(0xfff1b8), "scb": hex(0xd8e8ff), "world": hex(0xe7dbff),
                       "nyt": hex(0xe8e4f0), "bbc": hex(0xffd9d9), "msnow": hex(0xd6e9ff)],
              glows: ["svt": hex(0xffb3d1), "sr": hex(0xa8dcff), "dn": hex(0xffc89e), "scb": hex(0xbff2d4), "world": hex(0xffc2e6),
                       "nyt": hex(0xd0c8e8), "bbc": hex(0xffbdbd), "msnow": hex(0xb8d8ff)],
              glowAlpha: 0.95, flatBackground: true, chip: .highlight, photo: false, scanlines: false, kickerRule: false, cursor: false,
              headline: FontSpec(family: .rounded, weight: .black), headlineScale: 1.1, headlineLineHeight: 1.0, headlineKern: -0.02,
              lede: FontSpec(family: .rounded, weight: .medium), ledeScale: 1,
              ui: FontSpec(family: .rounded, weight: .heavy), number: FontSpec(family: .rounded, weight: .heavy),
              highlight: hex(0x3b2a4a), onHighlight: hex(0xfff8f2), chipRadius: 0.5,
              secondGlows: ["svt": hex(0xfff0a8), "sr": hex(0xe0c8ff), "dn": hex(0xc3f0ff), "scb": hex(0xffd1dc), "world": hex(0xbfeee0),
                       "nyt": hex(0xf3e6c8), "bbc": hex(0xfff0c0), "msnow": hex(0xe0f5e8)]),

        Theme(id: "matrix", name: "Matrix", blurb: "Phosphor green on black, falling glyphs in the background and glowing text.",
              background: hex(0x010501), text: hex(0x00ff41), mutedAlpha: 0.6, ruleAlpha: 0.25, ledeAlpha: 0.82,
              accents: ["svt": hex(0x00ff41), "sr": hex(0x7dffb0), "dn": hex(0xb6ff3b), "scb": hex(0x3bffd8), "world": hex(0x00ff41),
                       "nyt": hex(0x00ff41), "bbc": hex(0x7dffb0), "msnow": hex(0xb6ff3b)],
              glows: ["default": hex(0x00701c)],
              glowAlpha: 0.22, flatBackground: false, chip: .filled, photo: false, scanlines: false, kickerRule: false, cursor: false,
              headline: FontSpec(family: .mono, weight: .bold), headlineScale: 0.8, headlineLineHeight: 1.16, headlineKern: 0,
              lede: FontSpec(family: .mono, weight: .regular), ledeScale: 0.84,
              ui: FontSpec(family: .mono, weight: .bold), number: FontSpec(family: .mono, weight: .bold),
              textGlow: true, rain: true),

        Theme(id: "skyddsrum", name: "Shelter", blurb: "Retro-futuristic portable terminal: phosphor-green tube with bezel, vignette, source tabs and flicker.",
              background: hex(0x03140a), text: hex(0x41ff8a), mutedAlpha: 0.6, ruleAlpha: 0.3, ledeAlpha: 0.85,
              accents: ["default": hex(0x41ff8a)],
              glows: ["default": hex(0x0d6b33)],
              glowAlpha: 0.35, flatBackground: false, chip: .filled, photo: false, scanlines: true, kickerRule: false, cursor: true,
              headline: FontSpec(family: .mono, weight: .heavy), headlineScale: 0.72, headlineLineHeight: 1.18, headlineKern: 0.02,
              lede: FontSpec(family: .mono, weight: .medium), ledeScale: 0.82,
              ui: FontSpec(family: .mono, weight: .heavy), number: FontSpec(family: .mono, weight: .heavy),
              textGlow: true, bezel: true, sourceTabs: true, flicker: true, uppercaseHeadline: true),

        Theme(id: "terminal", name: "Terminal", blurb: "Amber text on black, monospace and sweeping CRT lines.",
              background: hex(0x060906), text: hex(0xffb547), mutedAlpha: 0.55, ruleAlpha: 0.22, ledeAlpha: 0.85,
              accents: ["svt": hex(0xff5f56), "sr": hex(0x5ad1ff), "dn": hex(0xffd84d), "scb": hex(0x7dff8a), "world": hex(0xc792ff),
                       "nyt": hex(0xe0e0e0), "bbc": hex(0xff6b6b), "msnow": hex(0x7ab0ff)],
              glows: ["default": hex(0x2a6b2f)],
              glowAlpha: 0.18, flatBackground: false, chip: .filled, photo: false, scanlines: true, kickerRule: false, cursor: true,
              headline: FontSpec(family: .mono, weight: .bold), headlineScale: 0.74, headlineLineHeight: 1.2, headlineKern: 0,
              lede: FontSpec(family: .mono, weight: .regular), ledeScale: 0.82,
              ui: FontSpec(family: .mono, weight: .bold), number: FontSpec(family: .mono, weight: .medium)),
    ]
}

func hex(_ value: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255, alpha: 1)
}
