import SwiftUI

/// The real NewsCanvas, scaled down, updating as settings change.
struct LivePreview: NSViewRepresentable {
    let settings: NyheterSettings
    let log: FetchLog

    func makeNSView(context: Context) -> NewsCanvas {
        let canvas = NewsCanvas(frame: NSRect(x: 0, y: 0, width: 640, height: 360), settings: settings)
        canvas.onFetch = { [weak log, weak canvas] fetched, rotation, hits, at in
            log?.update(fetched: fetched, rotation: rotation, hits: hits, failed: canvas?.failedFeeds ?? [], at: at)
        }
        log.refresh = { [weak canvas] in canvas?.refresh() }
        context.coordinator.start(canvas)
        return canvas
    }

    func updateNSView(_ canvas: NewsCanvas, context: Context) {
        if canvas.settings != settings { canvas.apply(settings) }
    }

    func makeCoordinator() -> Ticker { Ticker() }

    static func dismantleNSView(_ canvas: NewsCanvas, coordinator: Ticker) { coordinator.stop() }
}

final class Ticker {
    private var timer: Timer?

    func start(_ canvas: NewsCanvas) {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak canvas] _ in canvas?.tick() }
    }

    func stop() { timer?.invalidate() }
}

/// Shows the screen saver full screen until a key is pressed or the mouse is clicked.
final class FullScreenPreview: NSWindow {
    private static var current: FullScreenPreview?
    private let ticker = Ticker()

    static func show(_ settings: NyheterSettings) {
        guard current == nil, let screen = NSScreen.main else { return }
        let window = FullScreenPreview(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = NewsCanvas(frame: NSRect(origin: .zero, size: screen.frame.size), settings: settings)
        window.contentView = canvas
        window.level = .screenSaver
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.ticker.start(canvas)
        NSCursor.hide()
        current = window
    }

    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { dismiss() }
    override func mouseDown(with event: NSEvent) { dismiss() }

    private func dismiss() {
        ticker.stop()
        NSCursor.unhide()
        orderOut(nil)
        Self.current = nil
    }
}
