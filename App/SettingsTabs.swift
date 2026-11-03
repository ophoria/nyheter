import SwiftUI

struct ThemeTab: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $store.settings.showQRCode) {
                            Label { Text(L("Show a QR code to the story in the right column")) } icon: { LucideIcon("panel-right") }
                        }
                        Toggle(isOn: $store.settings.headlineOnly) {
                            Label { Text(L("Show headlines only")) } icon: { LucideIcon("heading") }
                        }
                        Toggle(isOn: $store.settings.showProgress) {
                            Label { Text(L("Show the progress line at the bottom")) } icon: { LucideIcon("gauge") }
                        }
                        textWidth
                    }
                    .toggleStyle(.switch)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                } label: {
                    SectionHeader(L("Layout"), icon: "layout-template")
                }
                GroupBox {
                    Toggle(isOn: $store.settings.randomTheme) {
                        Label { Text(L("Pick a random theme each time the screen saver starts")) } icon: { LucideIcon("shuffle") }
                    }
                    .toggleStyle(.switch)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    if store.settings.randomTheme {
                        Text(L("Tick the themes that may be picked (%d selected).", store.settings.randomThemeIDs.count))
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding([.horizontal, .bottom], 6)
                    }
                } label: {
                    SectionHeader(L("Theme"), icon: "palette")
                }
                ForEach(Theme.all, id: \.id) { theme in
                    if store.settings.randomTheme {
                        let included = store.settings.randomThemeIDs.contains(theme.id)
                        ThemeCard(theme: theme, selected: included, marker: included ? "square-check" : "square", sources: sourceIDs)
                            .onTapGesture { toggleRandom(theme.id) }
                    } else {
                        ThemeCard(theme: theme, selected: store.settings.themeID == theme.id,
                                  marker: store.settings.themeID == theme.id ? "check" : nil, sources: sourceIDs)
                            .onTapGesture {
                                store.settings.themeID = theme.id
                                if theme.hidesColumn { store.settings.showQRCode = false }
                            }
                    }
                }
            }
            .padding(4)
        }
    }

    /// Width of the headline and text as a share of the screen's width, up to the widest that fits
    /// (less beside the QR code column, mirroring NewsCanvas.mainWidth). 0 means the widest.
    private var textWidth: some View {
        let s = store.settings
        let beside = s.showQRCode || Theme.named(s.themeID).photoWash
        let widest = beside ? NyheterSettings.textWidthBesideColumn : NyheterSettings.textWidthFull
        let width = s.textWidth > 0 ? min(s.textWidth, widest) : widest
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label { Text(L("Width of headline and text")) } icon: { LucideIcon("maximize-2") }
                Slider(value: Binding(get: { Double(width) }, set: { store.settings.textWidth = Int($0.rounded()) }),
                       in: Double(NyheterSettings.textWidthRange.lowerBound)...Double(widest), step: 1)
                Text("\(width) %").monospacedDigit().frame(width: 44, alignment: .trailing)
                Button(L("Reset")) { store.settings.textWidth = 0 }
                    .disabled(s.textWidth == 0)
            }
            Text(L("Share of the screen's width. Reset goes back to %d %%, the widest that fits.", widest))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    /// Colour dots on the cards: the sources in use, plus the counter slide.
    private var sourceIDs: [String] { store.settings.enabledProviders.map(\.id) + ["world"] }

    /// Adds or removes a theme from the random pool, always keeping at least one.
    private func toggleRandom(_ id: String) {
        var ids = store.settings.randomThemeIDs
        if ids.contains(id) {
            guard ids.count > 1 else { return }
            ids.removeAll { $0 == id }
        } else {
            ids.append(id)
        }
        store.settings.randomThemeIDs = Theme.all.map(\.id).filter(ids.contains)
    }
}

private struct ThemeCard: View {
    let theme: Theme
    let selected: Bool
    let marker: String?
    let sources: [String]

    private var first: String { sources.first ?? "svt" }

    private var chipText: NSColor {
        switch theme.chip {
        case .filled: return theme.background
        case .highlight: return theme.onHighlight
        case .inverted, .underline: return theme.accent(first)
        }
    }

    private var chipBackground: NSColor? {
        switch theme.chip {
        case .filled: return theme.accent(first)
        case .inverted: return theme.text
        case .highlight: return theme.mark(first)
        case .underline: return nil
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                Color(nsColor: theme.flatBackground ? theme.accent(first) : theme.background)
                if theme.photoWash {
                    // Stand-in for the faint photo behind the page.
                    LinearGradient(colors: [Color(nsColor: hex(0x5f7a8f)), Color(nsColor: hex(0x6b7f5a))], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .opacity(0.25)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(Sources.label(first))
                        .font(Font(theme.ui.font(8) as CTFont))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .foregroundColor(Color(nsColor: chipText))
                        .background(chipBackground.map { Color(nsColor: $0) } ?? .clear)
                    Text(L("Headline"))
                        .font(Font(theme.headline.font(22 * theme.headlineScale) as CTFont))
                        .foregroundColor(Color(nsColor: theme.text))
                }
                .padding(10)
            }
            .frame(width: 130, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(L(theme.name)).font(.headline)
                Text(L(theme.blurb)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    ForEach(sources, id: \.self) { source in
                        Circle().fill(Color(nsColor: theme.accent(source))).frame(width: 9, height: 9)
                    }
                }
            }
            Spacer(minLength: 0)
            if let marker {
                LucideIcon(marker, size: 18).foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.accentColor.opacity(0.15) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
    }
}

struct TimingTab: View {
    @EnvironmentObject private var store: SettingsStore
    /// Which formula is being edited; nil follows the active layout.
    @State private var editingHeadlines: Bool?

    private typealias Field = WritableKeyPath<NyheterSettings, Double>

    private func formula(_ headlines: Bool) -> (base: Field, perWord: Field, min: Field, max: Field) {
        headlines
            ? (\.headlineBaseSeconds, \.headlineSecondsPerWord, \.headlineMinSeconds, \.headlineMaxSeconds)
            : (\.baseSeconds, \.secondsPerWord, \.minSeconds, \.maxSeconds)
    }

    private func bind(_ field: Field) -> Binding<Double> {
        Binding(get: { store.settings[keyPath: field] }, set: { store.settings[keyPath: field] = $0 })
    }

    var body: some View {
        let s = store.settings
        Form {
            Section {
                Toggle(L("Adapt the time to the text length"), isOn: $store.settings.adaptive)
                if !s.adaptive {
                    Stepper(value: $store.settings.fixedSeconds, in: 3...300, step: 1) {
                        LabeledContent(L("Time per story"), value: "\(seconds(s.fixedSeconds)) s")
                    }
                }
            } header: {
                SectionHeader(L("Display time"), icon: "timer")
            } footer: {
                Text(s.adaptive ? L("Stories with more text are shown longer, short ones shorter.") : L("All stories are shown for the same time."))
            }

            if s.adaptive {
                let headlines = editingHeadlines ?? s.headlineOnly
                let f = formula(headlines)
                Section {
                    Picker(L("Formula for"), selection: Binding(get: { headlines }, set: { editingHeadlines = $0 })) {
                        Text(s.headlineOnly ? L("Headline and text") : L("Headline and text (in use)")).tag(false)
                        Text(s.headlineOnly ? L("Headlines only (in use)") : L("Headlines only")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Stepper(value: bind(f.base), in: 0...60, step: 0.5) {
                        LabeledContent(L("Base time"), value: "\(seconds(s[keyPath: f.base])) s")
                    }
                    Stepper(value: bind(f.perWord), in: 0...3, step: 0.05) {
                        LabeledContent(L("Time per word"), value: "\(seconds(s[keyPath: f.perWord])) s")
                    }
                    Stepper(value: bind(f.min), in: 1...s[keyPath: f.max], step: 1) {
                        LabeledContent(L("Minimum"), value: "\(seconds(s[keyPath: f.min])) s")
                    }
                    Stepper(value: bind(f.max), in: s[keyPath: f.min]...600, step: 1) {
                        LabeledContent(L("Maximum"), value: "\(seconds(s[keyPath: f.max])) s")
                    }
                } header: {
                    SectionHeader(L("Formula"), icon: "sigma")
                } footer: {
                    Text(L("The layout decides which formula is used: “Show headlines only” under Theme. Both are saved, so you can set up the other one in advance."))
                }
                Section {
                    Text(L("time = %@ s + %@ s × number of words\nlimited to %@–%@ s", seconds(s[keyPath: f.base]), seconds(s[keyPath: f.perWord]), seconds(s[keyPath: f.min]), seconds(s[keyPath: f.max])))
                        .font(.system(.body, design: .monospaced))
                    ForEach(headlines ? [5, 8, 13] : [20, 50, 80, 110], id: \.self) { words in
                        LabeledContent(L("%d words", words), value: "\(seconds(s.duration(words: words, headlineOnly: headlines))) s")
                    }
                } header: {
                    SectionHeader(L("How it is calculated"), icon: "calculator")
                } footer: {
                    Text(headlines
                         ? L("Headlines are usually 5–13 words long.")
                         : L("Only visible words count: text cut off with … on screen is not counted. Headline + text is usually 20–110 words."))
                }
            }

            Section {
                Stepper(value: $store.settings.counterSeconds, in: 3...300, step: 1) {
                    LabeledContent(L("Display time"), value: "\(seconds(s.counterSeconds)) s")
                }
            } header: {
                SectionHeader(L("The world right now"), icon: "globe")
            }
        }
        .formStyle(.grouped)
    }
}

struct WorldTab: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        let s = store.settings
        Form {
            Section {
                Toggle(L("Show “The world right now”"), isOn: $store.settings.counters)
                if s.counters {
                    Stepper(value: $store.settings.counterEvery, in: 1...50) {
                        LabeledContent(L("Shown after every"), value: L("%d stories", s.counterEvery))
                    }
                }
            } header: {
                SectionHeader(L("The world right now"), icon: "globe")
            } footer: {
                Text(L("The numbers count up live, like on Worldometers: they are calculated from published yearly figures (UN, Global Carbon Project, Global Forest Watch, ITU, SCB) and are estimates."))
            }
            if s.counters {
                Section {
                    ForEach(WorldCounter.all.filter { $0.isRelevant(to: s) }) { counter in
                        Toggle(isOn: Binding(
                            get: { store.settings.counterIDs.contains(counter.id) },
                            set: { on in
                                // Keep the catalogue order so the grid stays stable.
                                let chosen = Set(store.settings.counterIDs.filter { $0 != counter.id } + (on ? [counter.id] : []))
                                store.settings.counterIDs = WorldCounter.all.map(\.id).filter(chosen.contains)
                            })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L(counter.label))
                                Text(counter.source).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(!s.counterIDs.contains(counter.id) && s.counterIDs.count >= 8)
                    }
                } header: {
                    SectionHeader(L("Numbers to show (at most 8)"), icon: "hash")
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A Lucide icon that takes the surrounding foreground colour.
struct LucideIcon: View {
    let name: String
    var size: CGFloat = 15

    init(_ name: String, size: CGFloat = 15) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image(nsImage: Lucide.image(name) ?? NSImage())
            .renderingMode(.template)
            .resizable()
            .frame(width: size, height: size)
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String

    init(_ title: String, icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        Label { Text(title) } icon: { LucideIcon(icon, size: 14) }
    }
}

/// Number with at most two decimals in the app's language: 0,3 / 12 / 7,25.
func seconds(_ value: Double) -> String {
    let f = NumberFormatter()
    f.locale = L10n.locale
    f.maximumFractionDigits = 2
    f.minimumFractionDigits = 0
    return f.string(from: NSNumber(value: value)) ?? "\(value)"
}
