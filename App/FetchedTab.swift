import SwiftUI

/// What the live preview last fetched, for the Hämtat tab.
final class FetchLog: ObservableObject {
    @Published private(set) var fetched: [Story] = []
    @Published private(set) var positions: [String: Int] = [:]    // story key → place in the rotation (1-based)
    @Published private(set) var blockedBy: [String: String] = [:]   // headline → filter pattern
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var failedFeeds: Set<String> = []
    var refresh: (() -> Void)?

    /// Keyed by headline, so a story counts as shown even when its copy from another feed was the one kept.
    static func key(_ story: Story) -> String { story.title }

    func update(fetched: [Story], rotation: [Story], hits: [Filters.Hit], failed: Set<String>, at date: Date) {
        failedFeeds = failed
        self.fetched = fetched
        blockedBy = Dictionary(hits.map { ($0.story.title, $0.filter.pattern) }) { first, _ in first }
        positions = Dictionary(rotation.enumerated().map { (Self.key($0.element), $0.offset + 1) }) { first, _ in first }
        fetchedAt = date
    }
}

struct FetchedTab: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var log: FetchLog
    @State private var onlyShown = false

    private struct Group: Identifiable {
        let id: String
        let stories: [Story]
    }

    /// One group per feed, in the order feeds are requested, each newest first.
    private var groups: [Group] {
        let order = Sources.requests(for: store.settings).map(\.feed)
        let byFeed = Dictionary(grouping: log.fetched, by: \.feed)
        return (order + byFeed.keys.filter { !order.contains($0) }.sorted()).compactMap { feed in
            guard let stories = byFeed[feed] else { return nil }
            let sorted = stories.sorted { $0.date > $1.date }
            return Group(id: feed, stories: onlyShown ? sorted.filter { log.positions[FetchLog.key($0)] != nil } : sorted)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(summary).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Toggle(L("Only those shown"), isOn: $onlyShown).toggleStyle(.checkbox)
                Button { log.refresh?() } label: { LucideIcon("refresh-cw", size: 14) }
                    .help(L("Fetch again now"))
            }
            .padding(.horizontal, 4)

            if log.fetched.isEmpty {
                VStack(spacing: 8) {
                    LucideIcon("inbox", size: 28).foregroundStyle(.secondary)
                    Text(L("Nothing fetched yet.")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(Array(group.stories.enumerated()), id: \.offset) { _, story in
                                row(story)
                            }
                        } header: {
                            HStack {
                                Text(Sources.feedName(group.id))
                                Spacer()
                                let all = log.fetched.filter { $0.feed == group.id }
                                Text(L("%d of %d shown", all.filter { log.positions[FetchLog.key($0)] != nil }.count, all.count))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private func row(_ story: Story) -> some View {
        StoryRow(story: story, position: log.positions[FetchLog.key(story)], blockedBy: log.blockedBy[story.title], time: time(story.date))
    }

    private var summary: String {
        guard let at = log.fetchedAt else { return L("Fetching…") }
        let shown = log.positions.count
        return L("%d fetched, %d in the rotation", log.fetched.count, shown) + " · " + time(at)
    }

    private func time(_ date: Date) -> String {
        if date == .distantPast { return "–" }
        let sv = L10n.locale
        return Calendar.current.isDateInToday(date)
            ? date.formatted(.dateTime.locale(sv).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            : date.formatted(.dateTime.locale(sv).day().month(.abbreviated))
    }
}

/// A fetched story; clicking it opens the article on the source's site.
private struct StoryRow: View {
    let story: Story
    let position: Int?
    let blockedBy: String?
    let time: String
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(story.title)
                    .lineLimit(2)
                    .underline(hovering && story.link != nil)
                HStack(spacing: 4) {
                    Text(L(story.category))
                    if hovering, let host = story.link?.host {
                        LucideIcon("external-link", size: 10)
                        Text(host.replacingOccurrences(of: "www.", with: ""))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if let blockedBy {
                LucideIcon("filter", size: 12)
                    .foregroundStyle(.red)
                    .help(L("Filtered by “%@”", Filters.displayPattern(blockedBy)))
            } else {
                Text(position.map { "#\($0)" } ?? "–")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(position == nil ? Color.secondary : Color.accentColor)
                    .help(position == nil ? L("Not shown: over the maximum, deselected region or duplicate") : L("Place %d in the rotation", position!))
            }
        }
        .opacity(position == nil && !hovering ? 0.5 : 1)
        .contentShape(Rectangle())
        .help(story.link?.absoluteString ?? "")
        .onHover { inside in
            hovering = inside
            guard story.link != nil else { return }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture {
            if let link = story.link { NSWorkspace.shared.open(link) }
        }
    }
}
