// Draws the 1024 px app icon. Usage: make-icon <out.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    // macOS icon grid: 824 px rounded square centred in 1024.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(srgbRed: 0.05, green: 0.055, blue: 0.067, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    shape.addClip()
    NSGradient(colors: [NSColor(srgbRed: 1, green: 0.42, blue: 0.3, alpha: 0.55), .clear])!
        .draw(fromCenter: NSPoint(x: 260, y: 820), radius: 0, toCenter: NSPoint(x: 260, y: 820), radius: 620, options: [])
    NSGradient(colors: [NSColor(srgbRed: 0.23, green: 0.3, blue: 1, alpha: 0.5), .clear])!
        .draw(fromCenter: NSPoint(x: 860, y: 160), radius: 0, toCenter: NSPoint(x: 860, y: 160), radius: 620, options: [])

    var descriptor = NSFont.systemFont(ofSize: 560, weight: .bold).fontDescriptor
    descriptor = descriptor.withDesign(.serif) ?? descriptor
    let font = NSFont(descriptor: descriptor, size: 560)!
    let letter = NSAttributedString(string: "N", attributes: [
        .font: font, .foregroundColor: NSColor(srgbRed: 0.953, green: 0.933, blue: 0.902, alpha: 1),
    ])
    let bounds = letter.size()
    letter.draw(at: NSPoint(x: (size - bounds.width) / 2, y: 300))

    NSColor(srgbRed: 1, green: 0.416, blue: 0.302, alpha: 1).setFill()
    NSRect(x: 250, y: 250, width: 524, height: 22).fill()
    NSColor(srgbRed: 0.953, green: 0.933, blue: 0.902, alpha: 0.25).setFill()
    NSRect(x: 250, y: 205, width: 340, height: 14).fill()
    return true
}
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
