import ScreenSaver

/// Thin screen saver wrapper around NewsCanvas. Settings are edited in
/// Nyheter.app and read from its settings file.
@objc(NyheterSaverView)
final class NyheterSaverView: ScreenSaverView {
    private var canvas: NewsCanvas!
    private var settingsDate = NyheterSettings.modificationDate
    private var lastSettingsCheck = Date()

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 0.1
        canvas = NewsCanvas(frame: bounds, settings: .load())
        canvas.recordsSeen = !isPreview
        canvas.autoresizingMask = [.width, .height]
        addSubview(canvas)

        // Sonoma+ legacyScreenSaver never calls stopAnimation and keeps old
        // instances alive; exiting on willstop is the established workaround.
        if !isPreview {
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.screensaver.willstop"),
                object: nil, queue: .main
            ) { _ in exit(0) }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func animateOneFrame() {
        // Pick up changes made in the app while the saver is running (e.g. its thumbnail).
        if Date().timeIntervalSince(lastSettingsCheck) > 3 {
            lastSettingsCheck = Date()
            let date = NyheterSettings.modificationDate
            if date != settingsDate {
                settingsDate = date
                canvas.apply(.load())
            }
        }
        canvas.tick()
    }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
        let text = NSTextField(wrappingLabelWithString: L("Themes, sources and display time are set in the Nyheter app."))
        let open = NSButton(title: L("Open Nyheter"), target: self, action: #selector(openApp(_:)))
        let done = NSButton(title: L("Done"), target: self, action: #selector(closeSheet(_:)))
        open.keyEquivalent = "\r"
        let buttons = NSStackView(views: [done, open])
        let stack = NSStackView(views: [text, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        panel.contentView = stack
        return panel
    }

    @objc private func openApp(_ sender: NSButton) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "local.nyheter.app") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        closeSheet(sender)
    }

    @objc private func closeSheet(_ sender: NSButton) {
        guard let sheet = sender.window else { return }
        if let parent = sheet.sheetParent { parent.endSheet(sheet) } else { sheet.close() }
    }
}
