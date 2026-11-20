import SwiftUI

@main
struct NyheterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = SettingsStore.shared
    @StateObject private var log = FetchLog.shared

    var body: some Scene {
        WindowGroup("Nyheter", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(log)
                .frame(minWidth: 1140, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
        // nyheter:// addresses go to the app delegate, not to a new window.
        .handlesExternalEvents(matching: [])
        .commands {
            CommandGroup(replacing: .help) { HelpButton(label: false).keyboardShortcut("?", modifiers: .command) }
            CommandGroup(after: .windowArrangement) { HistoryCommand() }
        }

        // What the screen saver showed: "What was that story?"
        Window(L("History"), id: HistoryView.windowID) {
            HistoryView().environmentObject(store)
        }
        .defaultSize(HistoryView.defaultSize)
        .handlesExternalEvents(matching: [])


        // The filter log in a large window, nearly filling the screen.
        Window(L("Filter log"), id: LogBrowser.windowID) {
            LogBrowser()
                .environmentObject(store)
                .environmentObject(log)
        }
        .defaultSize(LogBrowser.defaultSize)
        .defaultPosition(.center)
        .handlesExternalEvents(matching: [])

        Window(L10n.help("help.title"), id: HelpView.windowID) {
            HelpView().environmentObject(store)
        }
        .defaultSize(width: 1040, height: 780)
        .defaultPosition(.center)
        .handlesExternalEvents(matching: [])
    }
}

/// Window › History (⌘Y).
struct HistoryCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L("History")) { openWindow(id: HistoryView.windowID) }
            .keyboardShortcut("y", modifiers: .command)
    }
}

/// Holds the settings and saves every change straight to the shared file (and to the active profile).
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: NyheterSettings {
        didSet {
            // Keep the order lists in step with the sources in use. Reassigning re-runs this
            // observer once (a @Published setter), after which nothing changes and it stops.
            var normalized = settings
            normalized.includeActiveSources()
            if normalized != settings { settings = normalized; return }
            Sources.custom = settings.customFeeds
            L10n.override = Self.debugLanguage ?? settings.language
            if settings.menuBarHistory != oldValue.menuBarHistory { StatusMenu.shared.show(settings.menuBarHistory) }
            if settings != oldValue {
                settings.save()
                if let profile = settings.activeProfile, Profiles.exists(profile) { Profiles.save(settings, as: profile) }
            }
        }
    }

    /// Switches to a saved profile, keeping this Mac's language.
    func switchProfile(_ name: String) {
        guard var loaded = Profiles.load(name) else { return }
        loaded.language = settings.language
        loaded.logClearedAt = settings.logClearedAt
        loaded.activeProfile = name
        loaded.includeActiveSources()
        settings = loaded
    }

    /// Adds a .nyheter file as a profile (named after the file) and switches to it.
    func importProfile(from url: URL) {
        guard let imported = Profiles.load(from: url) else { return }
        let name = Profiles.unique(url.deletingPathExtension().lastPathComponent)
        Profiles.save(imported, as: name)
        switchProfile(name)
        NotificationCenter.default.post(name: .profilesChanged, object: nil)
    }

    private init() {
        var loaded = NyheterSettings.load()
        loaded.includeActiveSources()
        settings = loaded
        L10n.override = Self.debugLanguage ?? settings.language
    }

    /// NYHETER_LANG (debug aid) previews a language without saving it.
    private static let debugLanguage = ProcessInfo.processInfo.environment["NYHETER_LANG"]
}

struct ContentView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var log: FetchLog
    @Environment(\.openWindow) private var openWindow
    @State private var tab = Int(ProcessInfo.processInfo.environment["NYHETER_TAB"] ?? "") ?? 0

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                LivePreview(settings: store.settings, log: log)
                    // The shape of this Mac's screen, so an ultrawide layout previews as it will look.
                    .aspectRatio(NSScreen.main.map { $0.frame.width / $0.frame.height } ?? 16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.quaternary))
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                InstallBar()
                HStack(spacing: 18) {
                    LanguagePicker()
                    Spacer()
                    Button { openWindow(id: HistoryView.windowID) } label: {
                        Label { Text(L("History")) } icon: { LucideIcon("history") }
                    }
                    .controlSize(.large)
                    .help(L("Every story the screen saver showed in the last week"))
                    HelpButton().controlSize(.large)
                }
                ProfileMenu()
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(minWidth: 580, maxWidth: .infinity)

            Divider()

            TabView(selection: $tab) {
                ThemeTab().tabItem { Label { Text(L("Theme")) } icon: { LucideIcon("palette") } }.tag(0)
                TimingTab().tabItem { Label { Text(L("Time")) } icon: { LucideIcon("timer") } }.tag(1)
                SourcesTab().tabItem { Label { Text(L("Sources")) } icon: { LucideIcon("rss") } }.tag(2)
                OrderTab().tabItem { Label { Text(L("Order")) } icon: { LucideIcon("list-ordered") } }.tag(3)
                WorldTab().tabItem { Label { Text(L("World")) } icon: { LucideIcon("globe") } }.tag(4)
                FetchedTab().tabItem { Label { Text(L("Fetched")) } icon: { LucideIcon("inbox") } }.tag(5)
                FilterTab().tabItem { Label { Text(L("Filters")) } icon: { LucideIcon("filter") } }.tag(6)
            }
            .padding(16)
            .frame(width: 540)
        }
        .environment(\.layoutDirection, L10n.current.rightToLeft ? .rightToLeft : .leftToRight)
        .environment(\.locale, L10n.locale)
        .onAppear {
            // Lets the menu bar item open windows after this one is closed.
            StatusMenu.shared.openWindow = { [openWindow] id in openWindow(id: id) }
            snapshotIfRequested()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNyheterWindow)) { note in
            if let id = note.object as? String {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: id)
            }
        }
    }

    /// Debug aid: NYHETER_SNAPSHOT=<file.png> renders the window to a PNG and quits.
    private func snapshotIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["NYHETER_SNAPSHOT"] else { return }
        if ProcessInfo.processInfo.environment["NYHETER_LIGHT"] != nil { NSApp.appearance = NSAppearance(named: .aqua) }
        // NYHETER_SNAPSHOT_LOG=1 snapshots the large filter log window instead.
        // NYHETER_SNAPSHOT_HELP=1 snapshots the help window instead.
        let logWindow = ProcessInfo.processInfo.environment["NYHETER_SNAPSHOT_LOG"] != nil
        let helpWindow = ProcessInfo.processInfo.environment["NYHETER_SNAPSHOT_HELP"] != nil
        // NYHETER_SNAPSHOT_HISTORY=1 snapshots the History window instead.
        let historyWindow = ProcessInfo.processInfo.environment["NYHETER_SNAPSHOT_HISTORY"] != nil
        if logWindow { openWindow(id: LogBrowser.windowID) }
        if historyWindow { openWindow(id: HistoryView.windowID) }
        if helpWindow { openWindow(id: HelpView.windowID) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            let window = historyWindow ? NSApp.windows.first { $0.title == L("History") }
                : logWindow ? NSApp.windows.first { $0.title == L("Filter log") }
                : helpWindow ? NSApp.windows.first { $0.title == L10n.help("help.title") }
                : NSApp.windows.first { $0.title == "Nyheter" } ?? NSApp.windows.first
            guard let view = window?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
        }
    }
}

/// Language menu with flags; "Automatic" follows macOS.
struct LanguagePicker: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        HStack(spacing: 10) {
            LucideIcon("languages", size: 16).foregroundStyle(.secondary)
            Picker(L("Language"), selection: $store.settings.language) {
                let system = L10n.languages.first {
                    $0.code == Bundle.preferredLocalizations(from: L10n.languages.map(\.code), forPreferences: Locale.preferredLanguages).first
                } ?? L10n.languages[0]
                Text("🌐  " + L("Automatic (%@)", system.name)).tag(String?.none)
                Divider()
                ForEach(L10n.languages) { language in
                    Text(language.flag + "  " + language.name).tag(String?.some(language.code))
                }
            }
            .fixedSize()
        }
    }
}
