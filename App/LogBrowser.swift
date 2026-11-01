import SwiftUI

/// The whole filter log as a sortable, searchable table in its own large window.
struct LogBrowser: View {
    static let windowID = "filter-log"
    static var defaultSize: CGSize {
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(width: screen.width * 0.92, height: screen.height * 0.9)
    }

    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var log: FetchLog
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var entries: [BlockedEntry] = []
    @State private var search = ""
    @State private var selection = Set<BlockedEntry.ID>()
    @State private var sortOrder = [KeyPathComparator(\BlockedEntry.blockedAt, order: .reverse)]

    private var shown: [BlockedEntry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let list = query.isEmpty ? entries : entries.filter { entry in
            [entry.title, entry.pattern, entry.matched ?? "", Sources.label(entry.source), Sources.feedName(entry.feed)]
                .contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        return list.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SectionHeader(L("Log (%d / %d)", entries.count, BlockLog.capacity), icon: "scroll-text")
                    .font(.title3.weight(.semibold))
                Spacer()
                HStack(spacing: 6) {
                    LucideIcon("search", size: 13).foregroundStyle(.secondary)
                    TextField(L("Search the log"), text: $search).textFieldStyle(.plain).frame(width: 260)
                }
                .padding(6)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                Button(L("Close")) { dismissWindow(id: Self.windowID) }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)

            Table(shown, selection: $selection, sortOrder: $sortOrder) {
                TableColumn(L("Filtered at"), value: \.blockedAt) { entry in
                    Text(BlockLog.timestamp(entry.blockedAt)).monospacedDigit()
                }
                .width(min: 130, ideal: 150)
                TableColumn(L("Matched text"), value: \.matchedSortKey) { entry in
                    Text(entry.matched ?? "–").bold().foregroundStyle(entry.matched == nil ? Color.secondary : Color.red)
                }
                .width(min: 90, ideal: 140)
                TableColumn(L("Filter"), value: \.pattern) { entry in
                    Text(Filters.displayPattern(entry.pattern) + "  " + Filters.displayPlace(entry.place))
                        .font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .help(entry.pattern)
                }
                .width(min: 160, ideal: 280)
                TableColumn(L("Source"), value: \.feed) { entry in
                    Text(Sources.feedName(entry.feed))
                }
                .width(min: 110, ideal: 170)
                TableColumn(L("Headline"), value: \.title) { entry in
                    Text(entry.title).help(entry.link?.absoluteString ?? "")
                }
            }
            .contextMenu(forSelectionType: BlockedEntry.ID.self) { _ in
            } primaryAction: { ids in
                for entry in entries where ids.contains(entry.id) {
                    if let link = entry.link { NSWorkspace.shared.open(link) }
                }
            }

            Text(L("Double-click a row to open the story."))
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(minWidth: 900, minHeight: 500)
        .environment(\.layoutDirection, L10n.current.rightToLeft ? .rightToLeft : .leftToRight)
        .task { await reload() }
        .onChange(of: log.fetchedAt) { Task { await reload() } }
    }

    private func reload() async {
        let clearedAt = store.settings.logClearedAt
        entries = await Task.detached(priority: .userInitiated) { BlockLog.loadAll(clearedAt: clearedAt) }.value
    }
}

private extension BlockedEntry {
    var matchedSortKey: String { matched ?? "" }
}
