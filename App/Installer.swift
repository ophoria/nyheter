import SwiftUI

/// Copies the screen saver bundled inside the app into ~/Library/Screen Savers.
enum Installer {
    struct Status {
        let installedVersion: String?
        let bundledVersion: String?
        var installed: Bool { installedVersion != nil }
        var upToDate: Bool { installedVersion == bundledVersion }
    }

    private static var bundled: URL? { Bundle.main.url(forResource: "Nyheter", withExtension: "saver") }
    private static var folder: URL { NyheterSettings.realHome.appendingPathComponent("Library/Screen Savers") }
    private static var destination: URL { folder.appendingPathComponent("Nyheter.saver") }

    static func status() -> Status {
        func version(_ url: URL?) -> String? {
            guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
            let info = Bundle(url: url)?.infoDictionary
            return "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
        }
        return Status(installedVersion: version(destination), bundledVersion: version(bundled))
    }

    static func install() throws {
        guard let bundled else { throw CocoaError(.fileNoSuchFile) }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        // Also remove the early prototype, which had a different name.
        for old in [destination, folder.appendingPathComponent("NewsSaver.saver")] where fm.fileExists(atPath: old.path) {
            try fm.removeItem(at: old)
        }
        try fm.copyItem(at: bundled, to: destination)
        // The screen saver host caches loaded bundles; restart it so the new version is used.
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        kill.arguments = ["legacyScreenSaver"]
        try? kill.run()
    }

    static func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!)
    }

    /// macOS 26 moved "Show large clock" (the clock macOS draws over the screen saver) from
    /// Lock Screen to Wallpaper › Clock Appearance….
    static var clockInWallpaper: Bool { ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: 26, minorVersion: 0, patchVersion: 0)) }

    static func openClockSettings() {
        let pane = clockInWallpaper ? "com.apple.Wallpaper-Settings.extension" : "com.apple.Lock-Screen-Settings.extension"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:\(pane)")!)
    }
}

struct InstallBar: View {
    @EnvironmentObject private var store: SettingsStore
    @State private var status = Installer.status()
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                LucideIcon(status.installed && status.upToDate ? "circle-check" : "circle-arrow-down", size: 26)
                    .foregroundStyle(status.installed && status.upToDate ? Color.green : Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button {
                    do {
                        try Installer.install()
                        error = nil
                        if !status.installed { Installer.openSystemSettings() }
                    } catch {
                        self.error = error.localizedDescription
                    }
                    status = Installer.status()
                } label: {
                    Label {
                        Text(status.installed ? (status.upToDate ? L("Reinstall") : L("Update the screen saver")) : L("Install the screen saver"))
                    } icon: {
                        LucideIcon("download")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button { Installer.openSystemSettings() } label: {
                    Label { Text(L("System Settings…")) } icon: { LucideIcon("settings") }
                }
                .controlSize(.large)
                Button { Installer.openClockSettings() } label: {
                    Label { Text(L("Clock…")) } icon: { LucideIcon("clock") }
                }
                .controlSize(.large)
                .help(Installer.clockInWallpaper
                    ? L("Hide the clock macOS shows over the screen saver: Wallpaper › Clock Appearance… › Show large clock › On Lock Screen or Never.")
                    : L("Hide the clock macOS shows over the screen saver: Lock Screen › Show large clock › On Lock Screen or Never."))
                Spacer()
                Button {
                    FullScreenPreview.show(store.settings)
                } label: {
                    Label { Text(L("Show full screen")) } icon: { LucideIcon("maximize") }
                }
                .controlSize(.large)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }

    private var title: String {
        if !status.installed { return L("The screen saver is not installed") }
        return status.upToDate ? L("The screen saver is installed") : L("A new version is available in the app")
    }

    private var subtitle: String {
        status.installed
            ? L("Choose “Nyheter” under System Settings › Screen Saver. Changes here show up right away, in the screen saver too.")
            : L("Install it, then choose “Nyheter” under System Settings › Screen Saver.")
    }
}
