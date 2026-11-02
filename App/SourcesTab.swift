import SwiftUI

/// Sources in use, each with only its own options, and a menu to add the others.
/// Removing a source keeps its settings for when it is added again.
struct SourcesTab: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var log: FetchLog
    @State private var newFeed = ""
    @State private var finding = false
    @State private var findError: String?

    var body: some View {
        let s = store.settings
        Form {
            Section {
                Picker(L("Fetch new stories"), selection: $store.settings.refreshMinutes) {
                    ForEach(NyheterSettings.refreshChoices, id: \.self) { minutes in
                        Text(minutes < 60 ? L("every %d minutes", minutes) : minutes == 60 ? L("every hour") : minutes == 1440 ? L("once a day") : L("every %d hours", minutes / 60))
                            .tag(minutes)
                    }
                }
                Picker(L("Skip stories older than"), selection: $store.settings.maxAgeHours) {
                    ForEach(NyheterSettings.maxAgeChoices, id: \.self) { hours in
                        Text(hours == 0 ? L("No limit") : L("%d h", hours)).tag(hours)
                    }
                }
            } header: {
                SectionHeader(L("Updates"), icon: "refresh-cw")
            } footer: {
                Text(L("Undated stories and SCB's statistics are always kept."))
            }

            Section {
                HStack {
                    TextField(L("Feed or website address"), text: $newFeed, prompt: Text(L("Feed or website address")))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addFeed)
                    Button(action: addFeed) {
                        if finding { ProgressView().controlSize(.small) } else { Text(L("Add")) }
                    }
                    .disabled(finding || newFeed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let findError {
                    Label { Text(findError) } icon: { LucideIcon("triangle-alert", size: 12) }
                        .font(.callout).foregroundStyle(.orange)
                }
            } header: {
                SectionHeader(L("Your own feeds"), icon: "rss")
            } footer: {
                Text(L("Paste the address of any RSS, Atom or JSON feed, or of a website that has one. Each feed becomes a source of its own."))
            }

            let inactive = Sources.providers.filter { !s.isEnabled($0.id) }
            if !inactive.isEmpty {
                Section {
                    Menu {
                        ForEach(languageGroups(inactive), id: \.language) { group in
                            Section(group.name) {
                                ForEach(group.providers) { provider in
                                    Button(provider.flag + "  " + provider.name) {
                                        store.settings.updateSource(provider.id) { $0.enabled = true }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label { Text(L("Add source")) } icon: { LucideIcon("plus") }
                    }
                    .fixedSize()
                }
            }

            if s.enabledProviders.isEmpty {
                Section {
                    Text(L("No sources yet. Add one above.")).foregroundStyle(.secondary)
                }
            }

            ForEach(s.enabledProviders) { provider in
                Section {
                    ForEach(provider.feeds) { feed in
                        Toggle(isOn: feedBinding(provider, feed)) {
                            HStack(spacing: 6) {
                                Text(L(feed.name))
                                if failed(feed, of: provider) {
                                    LucideIcon("triangle-alert", size: 12).foregroundStyle(.orange)
                                    Text(L("Not responding right now")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if provider.localRegions, let local = provider.feeds.first(where: { $0.id == Sources.svtLocalFeed }), s.isOn(local, of: provider) {
                        Stepper(value: intBinding(provider.id, \.maxLocal), in: 0...40) {
                            LabeledContent(L("Maximum local stories"), value: "\(s.source(provider.id).maxLocal)")
                        }
                        DisclosureGroup {
                            ForEach(Sources.svtRegions, id: \.slug) { region in
                                Toggle(region.name, isOn: regionBinding(provider.id, region.slug))
                            }
                        } label: {
                            Label {
                                let regions = s.source(provider.id).regions
                                Text(regions.isEmpty ? L("Regions: all") : L("Regions: %@", regionSummary(regions)))
                            } icon: {
                                LucideIcon("map-pin")
                            }
                        }
                    }
                    if provider.isCustom, let feed = provider.feeds.first {
                        Text(feed.url).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    }
                    if provider.itemLimit {
                        Stepper(value: intBinding(provider.id, \.maxItems), in: 1...10) {
                            LabeledContent(L("Maximum"), value: "\(s.source(provider.id).maxItems)")
                        }
                    }
                } header: {
                    HStack {
                        Text(provider.flag + "  " + provider.name)
                        Spacer()
                        Button {
                            store.settings.updateSource(provider.id) { $0.enabled = false }
                        } label: {
                            Label { Text(L("Remove")) } icon: { LucideIcon("circle-minus", size: 12) }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help(L("Its settings are kept and come back if you add it again."))
                        if provider.isCustom {
                            Button {
                                store.settings.removeCustomFeed(provider.id)
                            } label: {
                                Label { Text(L("Delete")) } icon: { LucideIcon("trash-2", size: 12) }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                }
            }

            Section {
            } footer: {
                Text(L("The same headline from several sources is shown only once. The order is set under Order."))
            }
        }
        .formStyle(.grouped)
    }

    /// Finds the feed behind what was pasted and adds it as a source, switched on.
    private func addFeed() {
        let text = newFeed
        guard !finding, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        finding = true
        findError = nil
        Task { @MainActor in
            defer { finding = false }
            do {
                let feed = try await FeedFinder.find(text)
                if let existing = store.settings.customFeeds.first(where: { $0.url == feed.url }) {
                    store.settings.updateSource(existing.id) { $0.enabled = true }
                } else {
                    Sources.custom = store.settings.customFeeds + [feed]
                    store.settings.customFeeds.append(feed)
                }
                newFeed = ""
            } catch {
                findError = (error as? FeedFinder.Failure ?? .unreachable).message
            }
        }
    }

    private func failed(_ feed: Provider.Feed, of provider: Provider) -> Bool {
        if feed.id == Sources.svtLocalFeed {
            return store.settings.source(provider.id).regions.contains { log.failedFeeds.contains("svt-\($0)") }
        }
        return store.settings.isOn(feed, of: provider) && log.failedFeeds.contains(feed.id)
    }

    /// Inactive providers grouped by language, named in the app's language ("Swedish", "English" …).
    private func languageGroups(_ providers: [Provider]) -> [(language: String, name: String, providers: [Provider])] {
        Dictionary(grouping: providers, by: \.language)
            .map { code, list in (code, L10n.locale.localizedString(forLanguageCode: code)?.capitalized(with: L10n.locale) ?? code, list) }
            .sorted { $0.name < $1.name }
    }

    private func feedBinding(_ provider: Provider, _ feed: Provider.Feed) -> Binding<Bool> {
        Binding(
            get: { store.settings.isOn(feed, of: provider) },
            set: { on in store.settings.updateSource(provider.id) { $0.feeds[feed.id] = on } })
    }

    private func intBinding(_ id: String, _ field: WritableKeyPath<SourceSettings, Int>) -> Binding<Int> {
        Binding(
            get: { store.settings.source(id)[keyPath: field] },
            set: { value in store.settings.updateSource(id) { $0[keyPath: field] = value } })
    }

    private func regionBinding(_ id: String, _ slug: String) -> Binding<Bool> {
        Binding(
            get: { store.settings.source(id).regions.contains(slug) },
            set: { on in
                store.settings.updateSource(id) { config in
                    config.regions.removeAll { $0 == slug }
                    if on { config.regions.append(slug) }
                }
            })
    }

    private func regionSummary(_ slugs: [String]) -> String {
        let names = Sources.svtRegions.filter { slugs.contains($0.slug) }.map(\.name)
        return names.count > 3 ? L("%d selected", names.count) : names.joined(separator: ", ")
    }
}
