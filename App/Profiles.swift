import SwiftUI
import UniformTypeIdentifiers

/// Named sets of settings ("Work", "Home", "Election night"), each a .nyheter file in
/// ~/Library/Application Support/Nyheter/Profiles. The settings in use are also saved to the active profile.
enum Profiles {
    static let fileExtension = "nyheter"
    static let type = UTType(exportedAs: "local.nyheter.profile", conformingTo: .json)

    static var folder: URL { NyheterSettings.realHome.appendingPathComponent("Library/Application Support/Nyheter/Profiles", isDirectory: true) }

    static func url(_ name: String) -> URL { folder.appendingPathComponent(safe(name)).appendingPathExtension(fileExtension) }

    /// File names can't hold "/" or ":"; everything else may stay.
    private static func safe(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    static func names() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == fileExtension }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: url(name).path) }

    static func load(_ name: String) -> NyheterSettings? { load(from: url(name)) }

    static func load(from url: URL) -> NyheterSettings? { (try? Data(contentsOf: url)).flatMap(NyheterSettings.decode) }

    /// Saves without the parts that belong to this Mac rather than to the profile.
    static func save(_ settings: NyheterSettings, as name: String) { portable(settings).save(to: url(name)) }

    static func export(_ settings: NyheterSettings, to url: URL) { portable(settings).save(to: url) }

    private static func portable(_ settings: NyheterSettings) -> NyheterSettings {
        var copy = settings
        copy.activeProfile = nil
        copy.logClearedAt = nil
        return copy
    }

    static func delete(_ name: String) { try? FileManager.default.removeItem(at: url(name)) }

    static func rename(_ old: String, to new: String) { try? FileManager.default.moveItem(at: url(old), to: url(new)) }

    /// A name not taken yet: "Work", "Work 2", …
    static func unique(_ base: String) -> String {
        var name = base, n = 2
        while exists(name) { name = "\(base) \(n)"; n += 1 }
        return name
    }

    /// The address that switches to a profile, for Shortcuts' "Open URLs" action.
    static func link(_ name: String) -> String {
        "nyheter://profile/" + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? name)
    }
}

/// The profile menu beside the language menu: switch, save, rename, delete, import and export.
struct ProfileMenu: View {
    @EnvironmentObject private var store: SettingsStore
    @State private var names = Profiles.names()
    @State private var naming: Naming?
    @State private var newName = ""

    private enum Naming: Identifiable {
        case new, rename(String)
        var id: String { if case let .rename(name) = self { return "rename-" + name }; return "new" }
    }

    var body: some View {
        HStack(spacing: 10) {
            LucideIcon("user-round", size: 16).foregroundStyle(.secondary)
            Menu {
                if names.isEmpty {
                    Text(L("No profiles yet"))
                }
                ForEach(names, id: \.self) { name in
                    Toggle(name, isOn: Binding(get: { store.settings.activeProfile == name }, set: { _ in store.switchProfile(name) }))
                }
                Divider()
                Button(L("Save as new profile…")) { newName = ""; naming = .new }
                if let active = store.settings.activeProfile {
                    Button(L("Rename “%@”…", active)) { newName = active; naming = .rename(active) }
                    Button(L("Copy Shortcuts link for “%@”", active)) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Profiles.link(active), forType: .string)
                    }
                    Button(L("Stop using “%@”", active)) { store.settings.activeProfile = nil }
                    Button(L("Delete “%@”", active), role: .destructive) {
                        Profiles.delete(active)
                        store.settings.activeProfile = nil
                        reload()
                    }
                }
                Divider()
                Button(L("Import…"), action: importProfile)
                Button(L("Export…"), action: exportProfile)
            } label: {
                Text(store.settings.activeProfile.map { L("Profile: %@", $0) } ?? L("No profile"))
            }
            .fixedSize()
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .profilesChanged)) { _ in reload() }
        .alert(naming.map { if case .new = $0 { return L("Save as new profile") }; return L("Rename profile") } ?? "",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField(L("Name"), text: $newName)
            Button(L("Cancel"), role: .cancel) { naming = nil }
            Button(L("Save")) { commit() }
        } message: {
            Text(L("A profile keeps every setting except the language. Changes are saved to the profile in use."))
        }
    }

    private func reload() { names = Profiles.names() }

    private func commit() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { naming = nil }
        guard !name.isEmpty else { return }
        switch naming {
        case .new:
            let unique = Profiles.exists(name) ? Profiles.unique(name) : name
            Profiles.save(store.settings, as: unique)
            store.settings.activeProfile = unique
        case let .rename(old):
            guard name != old else { return }
            let unique = Profiles.exists(name) ? Profiles.unique(name) : name
            Profiles.rename(old, to: unique)
            store.settings.activeProfile = unique
        case nil:
            return
        }
        reload()
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Profiles.type, .json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store.importProfile(from: url) }
        reload()
    }

    private func exportProfile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Profiles.type]
        panel.nameFieldStringValue = (store.settings.activeProfile ?? "Nyheter") + "." + Profiles.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Profiles.export(store.settings, to: url)
    }
}

extension Notification.Name {
    static let profilesChanged = Notification.Name("NyheterProfilesChanged")
    static let openNyheterWindow = Notification.Name("NyheterOpenWindow")
}

/// nyheter:// addresses, for Shortcuts ("Open URLs"), the Terminal (`open nyheter://refresh`) or links:
///   nyheter://profile/<name>         switch to a profile
///   nyheter://refresh                fetch the news again now
///   nyheter://filter?word=<text>     hide stories with this word
///   nyheter://watchword?word=<text>  show stories with this word first
///   nyheter://history                open the History window
///   nyheter://preview                show the screen saver full screen
/// A .nyheter file opened in Finder is imported as a profile.
enum URLActions {
    static func handle(_ url: URL, store: SettingsStore) {
        if url.isFileURL {
            store.importProfile(from: url)
            return
        }
        guard url.scheme?.lowercased() == "nyheter" else { return }
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let item = { (name: String) in parts?.queryItems?.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespaces) }
        let path = url.path.split(separator: "/").map(String.init).first?.removingPercentEncoding
        switch url.host?.lowercased() {
        case "profile":
            if let name = path ?? item("name"), Profiles.exists(name) { store.switchProfile(name) }
        case "refresh":
            FetchLog.shared.refresh?()
        case "filter":
            if let word = item("word") ?? path, !word.isEmpty, !store.settings.filters.contains(where: { $0.pattern == word && !$0.regex }) {
                store.settings.filters.append(NewsFilter(pattern: word))
            }
        case "watchword":
            if let word = item("word") ?? path, !word.isEmpty, !store.settings.watchwords.contains(word) {
                store.settings.watchwords.append(word)
            }
        case "history":
            NotificationCenter.default.post(name: .openNyheterWindow, object: HistoryView.windowID)
        case "preview":
            FullScreenPreview.show(store.settings)
        default:
            return
        }
    }
}

/// Receives nyheter:// addresses and .nyheter files.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        StatusMenu.shared.show(SettingsStore.shared.settings.menuBarHistory)
    }

    /// Closing the last window keeps the app running when the menu bar item is there to come back from.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { URLActions.handle(url, store: SettingsStore.shared) }
    }
}
