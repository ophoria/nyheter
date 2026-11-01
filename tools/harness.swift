// Renders NewsCanvas offscreen and writes PNG snapshots, for testing without
// locking the screen. Compiled together with Shared/*.swift by build.sh.
// Usage: harness <out-prefix> <themeID> <counterEvery> <seconds...>
import AppKit

let args = CommandLine.arguments
guard args.count > 4 else { fatalError("usage: harness <out-prefix> <themeID> <counterEvery> <seconds...>") }
var settings = NyheterSettings()
settings.themeID = args[2]
settings.counterEvery = Int(args[3]) ?? 6
settings.fixedSeconds = 6
settings.counterSeconds = 6
// SOURCES=svt,sr,nyt,… picks the providers in use (default: SVT, SR, DN, SCB).
for id in (ProcessInfo.processInfo.environment["SOURCES"] ?? "svt,sr,dn,scb").split(separator: ",").map(String.init) {
    settings.updateSource(id) { $0.enabled = true }
}
for id in Sources.providerIDs where !(ProcessInfo.processInfo.environment["SOURCES"] ?? "svt,sr,dn,scb").contains(id) {
    settings.updateSource(id) { $0.enabled = false }
}
let env = ProcessInfo.processInfo.environment
settings.showUpcoming = env["NO_COLUMN"] == nil
settings.headlineOnly = env["HEADLINE_ONLY"] != nil
settings.showProgress = env["NO_PROGRESS"] == nil
settings.randomTheme = env["RANDOM_THEME"] != nil
settings.language = env["NYHETER_LANG"]

let frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
let canvas = NewsCanvas(frame: frame, settings: settings)
window.contentView = canvas

let start = Date()
for (n, mark) in args.dropFirst(4).compactMap(Double.init).enumerated() {
    while Date().timeIntervalSince(start) < mark {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        canvas.tick()
    }
    let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    canvas.layer!.render(in: ctx.cgContext)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(args[1])-\(n).png"))
    print("snapshot \(n) at \(mark)s")
}
