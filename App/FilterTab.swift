import SwiftUI

struct FilterTab: View {
    /// The log keeps up to BlockLog.capacity entries (all searchable) but shows only the newest ones.
    static let visibleEntries = 200

    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var log: FetchLog
    @State private var draft = NewsFilter(pattern: "")
    @State private var entries: [BlockedEntry] = []
    @State private var search = ""
    @State private var draftMatches: Int?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                TextField(L("Word or expression"), text: $draft.pattern)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(add)
                Picker(L("Type"), selection: $draft.regex) {
                    Text(L("Text")).tag(false)
                    Text(L("Regular expression")).tag(true)
                }
                Picker(L("Search in"), selection: $draft.scope) { scopeOptions }
                Toggle(L("Match upper and lower case"), isOn: $draft.caseSensitive)
                if store.settings.sourceLanguages.count > 1 {
                    Picker(L("Applies to"), selection: $draft.language) { languageOptions(draft.language) }
                }
                HStack {
                    if let error = draft.error {
                        Label { Text(error) } icon: { LucideIcon("triangle-alert", size: 13) }
                            .font(.caption).foregroundStyle(.red)
                    } else if !draft.pattern.isEmpty, let draftMatches {
                        Text(L("Matches right now: %d of %d fetched", draftMatches, log.fetched.count))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: add) {
                        Label { Text(L("Add")) } icon: { LucideIcon("plus", size: 13) }
                    }
                    .disabled(draft.pattern.isEmpty || draft.error != nil)
                }
            } header: {
                SectionHeader(L("New filter"), icon: "filter")
            } footer: {
                Text(L("Stories that match a filter are not shown. Text finds the word anywhere, e.g. “fotboll”. Regular expressions are fully supported, e.g. \\b(mord|skjutning)\\b or ^Live:."))
            }

            if !sectionList.isEmpty {
            Section {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
                    ForEach(sectionList, id: \.self) { section in
                        Toggle(isOn: sectionBinding(section)) {
                            HStack(spacing: 4) {
                                Text(L(section))
                                let count = log.fetched.filter { $0.category == section }.count
                                if count > 0 { Text("\(count)").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                SectionHeader(L("Hide whole sections"), icon: "layers")
            } footer: {
                Text(sectionsFooter)
            }
            }

            Section {
                if !store.settings.filters.contains(where: relevant) {
                    Text(L("No filters.")).foregroundStyle(.secondary)
                }
                // Filters for a language none of the sources in use is written in stay saved but hidden.
                ForEach($store.settings.filters) { $filter in
                    if relevant(filter) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Toggle("", isOn: $filter.enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                            if filter.regex { LucideIcon("regex", size: 13).foregroundStyle(.secondary) }
                            TextField(L("Pattern"), text: $filter.pattern)
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                            Spacer()
                            Text(L("%d matches", matches(filter))).font(.caption).foregroundStyle(.secondary)
                            Button {
                                store.settings.filters.removeAll { $0.id == filter.id }
                            } label: { LucideIcon("trash-2", size: 13) }
                                .buttonStyle(.borderless)
                                .help(L("Remove the filter"))
                        }
                        HStack {
                            Picker(L("Search in"), selection: $filter.scope) { scopeOptions }
                                .labelsHidden()
                                .fixedSize()
                            Toggle("Aa", isOn: $filter.caseSensitive)
                                .toggleStyle(.checkbox)
                                .help(L("Match upper and lower case"))
                            // Only worth choosing when sources in more than one language are in use.
                            if store.settings.sourceLanguages.count > 1 {
                                Picker(L("Applies to"), selection: $filter.language) { languageOptions(filter.language) }
                                    .labelsHidden()
                                    .fixedSize()
                                    .help(L("Applies to"))
                            }
                            if let error = filter.error {
                                Text(error).font(.caption).foregroundStyle(.red)
                            }
                        }
                        .controlSize(.small)
                    }
                    .opacity(filter.enabled ? 1 : 0.55)
                    }
                }
            } header: {
                SectionHeader(L("Filters (%d)", store.settings.filters.filter(relevant).count), icon: "list-ordered")
            }

            Section {
                HStack {
                    LucideIcon("search", size: 13).foregroundStyle(.secondary)
                    // In a grouped Form the title becomes a label beside an invisible plain field, so use a prompt.
                    TextField("", text: $search, prompt: Text(L("Search the log")))
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                let shown = filteredEntries
                if shown.isEmpty {
                    Text(entries.isEmpty ? L("Nothing has been filtered out yet.") : L("No matches.")).foregroundStyle(.secondary)
                }
                // Only the newest rows are drawn; building a thousand at once makes the tab slow to open.
                ForEach(shown.prefix(Self.visibleEntries)) { entry in
                    LogRow(entry: entry)
                }
            } header: {
                HStack {
                    SectionHeader(L("Log (%d / %d)", entries.count, BlockLog.capacity), icon: "scroll-text")
                    Spacer()
                    Button {
                        openWindow(id: LogBrowser.windowID)
                    } label: {
                        Label { Text(L("Open large")) } icon: { LucideIcon("maximize-2", size: 12) }
                    }
                    .buttonStyle(.borderless)
                    .disabled(entries.isEmpty)
                    Button(L("Clear")) {
                        BlockLog.clear()
                        store.settings.logClearedAt = Date()
                        reload()
                    }
                    .buttonStyle(.borderless)
                    .disabled(entries.isEmpty)
                }
            } footer: {
                Text(L("Each filtered story is logged once. The log holds %d entries; when it is full, new entries replace the oldest. Click an entry to open the story.", BlockLog.capacity) + " " + L("The %d latest are shown; search covers all.", Self.visibleEntries))
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .task(id: "\(draft.pattern)\(draft.regex)\(draft.scope)\(draft.caseSensitive)\(log.fetchedAt?.timeIntervalSince1970 ?? 0)") {
            // Count matches for the filter being typed after a short pause, off the main thread.
            draftMatches = nil
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let expression = draft.expression else { return }
            let filter = draft, stories = log.fetched
            let count = await Task.detached(priority: .userInitiated) {
                stories.filter { filter.match($0, using: expression) != nil }.count
            }.value
            if !Task.isCancelled { draftMatches = count }
        }

        .onChange(of: log.fetchedAt) { reload() }
        .onChange(of: store.settings.filters) {
            // Give the preview a moment to re-filter and log before reading the log back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: reload)
        }
    }

    /// "All sources" plus the languages of the sources in use (and the filter's own, if different).
    @ViewBuilder private func languageOptions(_ current: String?) -> some View {
        Text(L("All sources")).tag(String?.none)
        ForEach(Array(store.settings.sourceLanguages.union(current.map { [$0] } ?? [])).sorted(), id: \.self) { code in
            Text(L10n.locale.localizedString(forLanguageCode: code)?.capitalized(with: L10n.locale) ?? code).tag(String?.some(code))
        }
    }

    @ViewBuilder private var scopeOptions: some View {
        Text(L("Headline and text")).tag(NewsFilter.Scope.both)
        Text(L("Headline only")).tag(NewsFilter.Scope.title)
        Text(L("Text only")).tag(NewsFilter.Scope.body)
    }

    /// The standard sections plus any other non-regional section seen in the latest fetch.
    /// Sections of the sources in use, plus any other non-regional section seen in the latest fetch.
    private var sectionList: [String] {
        let known = Sources.sections(for: store.settings)
        let regions = Set(Sources.svtRegions.map(\.name))
        let seen = Set(log.fetched.map(\.category)).subtracting(regions).subtracting(Sources.sectionOrder).subtracting(["Nyheter"])
        return known + seen.sorted()
    }

    /// Explains where sections come from, naming only sources in use that have none.
    private var sectionsFooter: String {
        var text = L("Based on the section each source gives its stories. The number shows how many of the latest stories belong there.")
        let without = store.settings.enabledProviders.filter { $0.sections.isEmpty }.map(\.name)
        if !without.isEmpty {
            text += " " + L("%@ gives no section, so its stories are not affected.", ListFormatter.localizedString(byJoining: without))
        }
        return text
    }

    private func relevant(_ filter: NewsFilter) -> Bool {
        filter.language.map(store.settings.sourceLanguages.contains) ?? true
    }

    private func sectionBinding(_ section: String) -> Binding<Bool> {
        Binding(
            get: { store.settings.blockedSections.contains(section) },
            set: { on in
                store.settings.blockedSections.removeAll { $0 == section }
                if on { store.settings.blockedSections.append(section) }
            })
    }

    private var filteredEntries: [BlockedEntry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            [$0.title, $0.pattern, Sources.label($0.source), Sources.feedName($0.feed)]
                .contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    private func matches(_ filter: NewsFilter) -> Int {
        guard let expression = filter.expression else { return 0 }
        return log.fetched.filter { filter.match($0, using: expression) != nil }.count
    }

    private func add() {
        guard !draft.pattern.isEmpty, draft.error == nil else { return }
        store.settings.filters.append(draft)
        draft = NewsFilter(pattern: "", regex: draft.regex, caseSensitive: draft.caseSensitive, scope: draft.scope, language: draft.language)
    }

    /// Reads both logs off the main thread.
    private func reload() {
        let clearedAt = store.settings.logClearedAt
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { BlockLog.loadAll(clearedAt: clearedAt) }.value
            entries = loaded
        }
    }
}

private struct LogRow: View {
    let entry: BlockedEntry
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title).lineLimit(2).underline(hovering && entry.link != nil)
            HStack(spacing: 6) {
                LucideIcon("clock", size: 10)
                Text(BlockLog.timestamp(entry.blockedAt)).monospacedDigit()
                Text("·")
                Text(Sources.feedName(entry.feed))
                Text("·")
                LucideIcon("filter", size: 10)
                if let matched = entry.matched {
                    Text(matched).bold().foregroundStyle(.red).fixedSize()
                }
                Text(Filters.displayPattern(entry.pattern)).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                Text(Filters.displayPlace(entry.place)).fixedSize()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .help(entry.link?.absoluteString ?? "")
        .onHover { inside in
            hovering = inside
            guard entry.link != nil else { return }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture {
            if let link = entry.link { NSWorkspace.shared.open(link) }
        }
    }
}
