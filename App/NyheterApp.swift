import SwiftUI

@main
struct NyheterApp: App {
    @StateObject private var store = SettingsStore()
    @StateObject private var log = FetchLog()

    var body: some Scene {
        WindowGroup("Nyheter") {
            ContentView()
                .environmentObject(store)
                .environmentObject(log)
                .frame(minWidth: 1140, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .help) { HelpButton(label: false).keyboardShortcut("?", modifiers: .command) }
        }

        // The filter log in a large window, nearly filling the screen.
        Window(L("Filter log"), id: LogBrowser.windowID) {
            LogBrowser()
                .environmentObject(store)
                .environmentObject(log)
        }
        .defaultSize(LogBrowser.defaultSize)
        .defaultPosition(.center)

        Window(L10n.help("help.title"), id: HelpView.windowID) {
            HelpView().environmentObject(store)
        }
        .defaultSize(width: 1040, height: 780)
        .defaultPosition(.center)
    }
}

/// Holds the settings and saves every change straight to the shared file.
final class SettingsStore: ObservableObject {
    @Published var settings: NyheterSettings {
        didSet {
            // Keep the order lists in step with the sources in use. Reassigning re-runs this
            // observer once (a @Published setter), after which nothing changes and it stops.
            var normalized = settings
            normalized.includeActiveSources()
            if normalized != settings { settings = normalized; return }
            L10n.override = Self.debugLanguage ?? settings.language
            if settings != oldValue { settings.save() }
        }
    }

    init() {
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
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.quaternary))
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                InstallBar()
                HStack {
                    LanguagePicker()
                    Spacer()
                    HelpButton().controlSize(.large)
                }
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
        .onAppear(perform: snapshotIfRequested)
    }

    /// Debug aid: NYHETER_SNAPSHOT=<file.png> renders the window to a PNG and quits.
    private func snapshotIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["NYHETER_SNAPSHOT"] else { return }
        if ProcessInfo.processInfo.environment["NYHETER_LIGHT"] != nil { NSApp.appearance = NSAppearance(named: .aqua) }
        // NYHETER_SNAPSHOT_LOG=1 snapshots the large filter log window instead.
        // NYHETER_SNAPSHOT_HELP=1 snapshots the help window instead.
        let logWindow = ProcessInfo.processInfo.environment["NYHETER_SNAPSHOT_LOG"] != nil
        let helpWindow = ProcessInfo.processInfo.environment["NYHETER_SNAPSHOT_HELP"] != nil
        if logWindow { openWindow(id: LogBrowser.windowID) }
        if helpWindow { openWindow(id: HelpView.windowID) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            let window = logWindow ? NSApp.windows.first { $0.title == L("Filter log") }
                : helpWindow ? NSApp.windows.first { $0.title == L10n.help("help.title") } : NSApp.windows.first
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
