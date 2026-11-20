import SwiftUI

/// The screen saver's history of shown stories, reloaded when its file changes.
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [ShownEntry] = ShownHistory.entries()
    private var modified = ShownHistory.modified
    private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.reloadIfChanged() }
    }

    func reloadIfChanged() {
        let date = ShownHistory.modified
        guard date != modified else { return }
        modified = date
        entries = ShownHistory.entries()
    }
}

/// "What was that story?": everything the screen saver showed in the last week, searchable, by day.
struct HistoryView: View {
    static let windowID = "history"
    static let defaultSize = CGSize(width: 760, height: 640)

    @EnvironmentObject private var store: SettingsStore
    @ObservedObject private var history = HistoryStore.shared
    @State private var query = ""

    private struct Day: Identifiable {
        let id: Date
        let entries: [ShownEntry]
    }

    private var days: [Day] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let shown = q.isEmpty ? history.entries : history.entries.filter { entry in
            [entry.title, Sources.label(entry.source), L(entry.category)].contains { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        return Dictionary(grouping: shown) { Calendar.current.startOfDay(for: $0.shownAt) }
            .map { Day(id: $0.key, entries: $0.value.sorted { $0.shownAt > $1.shownAt }) }
            .sorted { $0.id > $1.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    LucideIcon("search", size: 13).foregroundStyle(.secondary)
                    TextField(L("Search headlines"), text: $query).textFieldStyle(.plain)
                }
                .padding(8)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                Toggle(L("Show in the menu bar"), isOn: $store.settings.menuBarHistory).toggleStyle(.checkbox).fixedSize()
            }
            .padding(14)
            Divider()
            if history.entries.isEmpty {
                VStack(spacing: 10) {
                    LucideIcon("history", size: 30).foregroundStyle(.secondary)
                    Text(L("Nothing yet. Stories the screen saver shows will be listed here.")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(days) { day in
                        Section {
                            ForEach(day.entries) { HistoryRow(entry: $0) }
                        } header: {
                            Text(dayTitle(day.id))
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            Divider()
            Text(L("The screen saver keeps the stories it showed for a week. Click one to open it on the source's site."))
                .font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .frame(minWidth: 560, minHeight: 400)
        .environment(\.layoutDirection, L10n.current.rightToLeft ? .rightToLeft : .leftToRight)
        .onAppear { history.reloadIfChanged() }
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return L("Today") }
        if Calendar.current.isDateInYesterday(day) { return L("Yesterday") }
        return day.formatted(.dateTime.locale(L10n.locale).weekday(.wide).day().month(.wide))
    }
}

private struct HistoryRow: View {
    let entry: ShownEntry
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.shownAt.formatted(.dateTime.locale(L10n.locale).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(Sources.label(entry.source))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).lineLimit(2).underline(hovering && entry.link != nil)
                HStack(spacing: 4) {
                    Text(L(entry.category))
                    if hovering, let host = entry.link?.host {
                        LucideIcon("external-link", size: 10)
                        Text(host.replacingOccurrences(of: "www.", with: ""))
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            guard entry.link != nil else { return }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture { if let link = entry.link { NSWorkspace.shared.open(link) } }
        .contextMenu {
            if let link = entry.link {
                Button(L("Open")) { NSWorkspace.shared.open(link) }
                Button(L("Copy link")) { copy(link.absoluteString) }
            }
            Button(L("Copy headline")) { copy(entry.title) }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// The menu bar item: the last stories the screen saver showed, rebuilt each time the menu opens.
/// (AppKit rather than SwiftUI's MenuBarExtra, which crashed at launch when bound to a setting.)
final class StatusMenu: NSObject, NSMenuDelegate {
    static let shared = StatusMenu()

    private var item: NSStatusItem?
    /// Opens a SwiftUI window by id; set by the main window when it appears.
    var openWindow: ((String) -> Void)?

    func show(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let image = Lucide.image("newspaper")
            image?.size = NSSize(width: 16, height: 16)
            item.button?.image = image
            item.button?.toolTip = L("Last shown by the screen saver")
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.item = item
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let recent = ShownHistory.entries().prefix(12)
        if recent.isEmpty {
            menu.addItem(withTitle: L("Nothing shown yet"), action: nil, keyEquivalent: "")
        } else {
            menu.addItem(withTitle: L("Last shown by the screen saver"), action: nil, keyEquivalent: "")
            for entry in recent {
                let time = entry.shownAt.formatted(.dateTime.locale(L10n.locale).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                let title = entry.title.count > 70 ? String(entry.title.prefix(68)) + "…" : entry.title
                let row = NSMenuItem(title: time + "  " + Sources.label(entry.source) + " · " + title,
                                     action: entry.link == nil ? nil : #selector(openLink(_:)), keyEquivalent: "")
                row.target = self
                row.representedObject = entry.link
                row.toolTip = entry.title
                menu.addItem(row)
            }
        }
        menu.addItem(.separator())
        add(menu, L("Open history…"), #selector(openHistory))
        add(menu, L("Open Nyheter"), #selector(openMain))
        menu.addItem(.separator())
        add(menu, L("Quit Nyheter"), #selector(quit))
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
        row.target = self
        menu.addItem(row)
    }

    @objc private func openLink(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func openHistory() { open(HistoryView.windowID) }

    @objc private func openMain() {
        if let window = NSApp.windows.first(where: { $0.title == "Nyheter" }) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            open("main")
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func open(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow?(id)
    }
}
