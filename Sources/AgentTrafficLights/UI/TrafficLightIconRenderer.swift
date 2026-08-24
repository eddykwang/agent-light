import AgentTrafficLightsCore
import AppKit

enum TrafficLightIconRenderer {
    static func image(status: AgentStatus, orientation: TrafficLightOrientation) -> NSImage {
        let size = orientation == .vertical ? NSSize(width: 22, height: 22) : NSSize(width: 28, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let housingRect: NSRect
        switch orientation {
        case .vertical:
            housingRect = NSRect(x: 5, y: 2, width: 12, height: 18)
        case .horizontal:
            housingRect = NSRect(x: 2, y: 5, width: 24, height: 12)
        }

        let housing = NSBezierPath(roundedRect: housingRect, xRadius: 3, yRadius: 3)
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        housing.fill()
        NSColor.white.withAlphaComponent(0.30).setStroke()
        housing.lineWidth = 0.8
        housing.stroke()

        lampCenters(for: orientation, in: size).forEach { lampStatus, center in
            drawLamp(
                lampStatus: lampStatus,
                aggregateStatus: status,
                active: isActiveLamp(lampStatus, for: status),
                center: center
            )
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func lampCenters(for orientation: TrafficLightOrientation, in size: NSSize) -> [(AgentStatus, NSPoint)] {
        switch orientation {
        case .vertical:
            return [
                (.failed, NSPoint(x: size.width / 2, y: 16)),
                (.needsInput, NSPoint(x: size.width / 2, y: 11)),
                (.working, NSPoint(x: size.width / 2, y: 6))
            ]
        case .horizontal:
            return [
                (.failed, NSPoint(x: 8, y: size.height / 2)),
                (.needsInput, NSPoint(x: 14, y: size.height / 2)),
                (.working, NSPoint(x: 20, y: size.height / 2))
            ]
        }
    }

    static func isActiveLamp(_ lamp: AgentStatus, for status: AgentStatus) -> Bool {
        switch status {
        case .failed, .needsInput, .working:
            return lamp == status
        case .idle, .unknown:
            return false
        }
    }

    static func lampColor(lampStatus: AgentStatus, aggregateStatus: AgentStatus, active: Bool) -> NSColor {
        if aggregateStatus == .unknown {
            return NSColor(calibratedWhite: 0.30, alpha: 1)
        }

        if !active {
            switch lampStatus {
            case .failed:
                return NSColor(red: 0.42, green: 0.08, blue: 0.07, alpha: 1)
            case .needsInput:
                return NSColor(red: 0.45, green: 0.33, blue: 0.04, alpha: 1)
            case .working:
                return NSColor(red: 0.05, green: 0.30, blue: 0.14, alpha: 1)
            case .idle, .unknown:
                return NSColor(calibratedWhite: 0.30, alpha: 1)
            }
        }

        switch lampStatus {
        case .failed:
            return NSColor(red: 1.0, green: 0.16, blue: 0.13, alpha: 1)
        case .needsInput:
            return NSColor(red: 1.0, green: 0.69, blue: 0.02, alpha: 1)
        case .working:
            return NSColor(red: 0.20, green: 0.82, blue: 0.35, alpha: 1)
        case .idle, .unknown:
            return NSColor(calibratedWhite: 0.45, alpha: 1)
        }
    }

    private static func drawLamp(lampStatus: AgentStatus, aggregateStatus: AgentStatus, active: Bool, center: NSPoint) {
        let radius: CGFloat = active ? 2.8 : 2.3
        let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let path = NSBezierPath(ovalIn: rect)

        if active {
            let glowRadius: CGFloat = 4.0
            let glowRect = NSRect(
                x: center.x - glowRadius,
                y: center.y - glowRadius,
                width: glowRadius * 2,
                height: glowRadius * 2
            )
            lampColor(lampStatus: lampStatus, aggregateStatus: aggregateStatus, active: true)
                .withAlphaComponent(0.28)
                .setFill()
            NSBezierPath(ovalIn: glowRect).fill()
        }

        lampColor(lampStatus: lampStatus, aggregateStatus: aggregateStatus, active: active).setFill()
        path.fill()

        if active {
            NSColor.white.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 0.6
            path.stroke()
        }
    }
}
