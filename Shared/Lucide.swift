import AppKit

/// Lucide icons (ISC licence, lucide-static 0.460.0), bundled as SVG in Resources/lucide.
enum Lucide {
    /// A tinted image, or a template image (tinted by SwiftUI) when no colour is given.
    static func image(_ name: String, color: NSColor? = nil) -> NSImage? {
        guard let url = Bundle(for: BundleToken.self).url(forResource: name, withExtension: "svg", subdirectory: "lucide"),
              var svg = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        if let color { svg = svg.replacingOccurrences(of: "currentColor", with: hex(color)) }
        let image = NSImage(data: Data(svg.utf8))
        image?.isTemplate = color == nil
        return image
    }

    private static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let v = [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
        return String(format: "#%02x%02x%02x\" stroke-opacity=\"%.3f", v[0], v[1], v[2], c.alphaComponent)
    }
}

private final class BundleToken {}
