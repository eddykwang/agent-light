import AppKit

enum ProviderIconRenderer {
    static func image(provider: String, size: NSSize, tint: NSColor = .labelColor) -> NSImage {
        let filename: String
        switch provider {
        case "claude-code":
            filename = "claude-ai.svg"
        case "codex":
            filename = "codex.png"
        case "copilot-cli":
            return systemSymbolImage(
                name: "chevron.left.forwardslash.chevron.right",
                size: size,
                tint: tint
            )
        default:
            return fallbackImage(size: size, tint: tint)
        }

        guard let source = loadImage(named: filename) else {
            return fallbackImage(size: size, tint: tint)
        }

        return tinted(source, size: size, tint: tint)
    }

    private static func loadImage(named filename: String) -> NSImage? {
        let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("ProviderIcons", isDirectory: true)
            .appendingPathComponent(filename)

        if let resourceURL, let image = NSImage(contentsOf: resourceURL) {
            return image
        }

        let localURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/ProviderIcons", isDirectory: true)
            .appendingPathComponent(filename)
        return NSImage(contentsOf: localURL)
    }

    private static func tinted(_ source: NSImage, size: NSSize, tint: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        tint.setFill()
        rect.fill(using: .sourceIn)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func fallbackImage(size: NSSize, tint: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        tint.setStroke()
        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = 1.2
        path.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func systemSymbolImage(name: String, size: NSSize, tint: NSColor) -> NSImage {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "Copilot CLI") else {
            return fallbackImage(size: size, tint: tint)
        }

        let configuration = NSImage.SymbolConfiguration(
            pointSize: min(size.width, size.height) * 0.78,
            weight: .medium
        )
        let configured = symbol.withSymbolConfiguration(configuration) ?? symbol
        return tinted(configured, size: size, tint: tint)
    }
}
