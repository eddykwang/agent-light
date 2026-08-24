import AppKit
import XCTest
@testable import AgentTrafficLights

final class DesktopLightLayoutTests: XCTestCase {
    func testContentAndWindowSizesFollowOrientation() {
        XCTAssertEqual(
            DesktopLightLayout.contentSize(for: .vertical),
            NSSize(width: 50, height: 126)
        )
        XCTAssertEqual(
            DesktopLightLayout.contentSize(for: .horizontal),
            NSSize(width: 126, height: 50)
        )
        XCTAssertEqual(
            DesktopLightLayout.windowSize(for: .vertical),
            NSSize(width: 66, height: 142)
        )
        XCTAssertEqual(
            DesktopLightLayout.windowSize(for: .horizontal),
            NSSize(width: 142, height: 66)
        )
    }

    func testWindowSizeClampsScaleRange() {
        XCTAssertEqual(
            DesktopLightLayout.windowSize(for: .horizontal, scale: 0.1),
            NSSize(width: 106.5, height: 49.5)
        )
        XCTAssertEqual(
            DesktopLightLayout.windowSize(for: .vertical, scale: 10),
            NSSize(width: 132, height: 284)
        )
    }

    func testMinimumScaleAddsCenteredRasterSafetyInset() {
        XCTAssertEqual(
            DesktopLightLayout.contentSafetyScale(for: 0.75),
            0.98,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            DesktopLightLayout.contentSafetyScale(for: 0.80),
            0.99,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            DesktopLightLayout.contentSafetyScale(for: 0.85),
            1.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            DesktopLightLayout.contentSafetyScale(for: 1.0),
            1.0,
            accuracy: 0.0001
        )
    }

    func testCornerResizePreservesAspectRatioAndOppositeCorner() {
        let initial = NSRect(x: 200, y: 300, width: 142, height: 66)
        let resized = DesktopLightLayout.resizedFrame(
            from: initial,
            corner: .bottomLeft,
            dragDelta: NSPoint(x: -71, y: -33),
            orientation: .horizontal
        )

        XCTAssertEqual(resized.size, NSSize(width: 213, height: 99))
        XCTAssertEqual(resized.maxX, initial.maxX)
        XCTAssertEqual(resized.maxY, initial.maxY)
        XCTAssertEqual(resized.width / resized.height, 142.0 / 66.0, accuracy: 0.0001)
    }

    func testCornerResizeStopsAtMinimumAndMaximumScale() {
        let initial = NSRect(x: 200, y: 300, width: 142, height: 66)
        let minimum = DesktopLightLayout.resizedFrame(
            from: initial,
            corner: .topRight,
            dragDelta: NSPoint(x: -1_000, y: -1_000),
            orientation: .horizontal
        )
        let maximum = DesktopLightLayout.resizedFrame(
            from: initial,
            corner: .topRight,
            dragDelta: NSPoint(x: 1_000, y: 1_000),
            orientation: .horizontal
        )

        XCTAssertEqual(minimum.size, NSSize(width: 106.5, height: 49.5))
        XCTAssertEqual(maximum.size, NSSize(width: 284, height: 132))
    }

    func testDefaultOriginUsesUpperRightSafeArea() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let origin = DesktopLightLayout.defaultOrigin(
            for: NSSize(width: 66, height: 142),
            in: frame
        )

        XCTAssertEqual(origin, NSPoint(x: 1352, y: 711))
    }

    func testOffscreenOriginReturnsToFallbackDisplay() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let origin = DesktopLightLayout.clampedOrigin(
            NSPoint(x: 2600, y: 1200),
            size: NSSize(width: 66, height: 142),
            visibleFrames: [frame]
        )

        XCTAssertEqual(origin, NSPoint(x: 1360, y: 719))
    }

    func testOriginStaysOnSecondaryDisplayWhenItIntersectsThere() {
        let primary = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let secondary = NSRect(x: 1440, y: -100, width: 1920, height: 1080)
        let origin = DesktopLightLayout.clampedOrigin(
            NSPoint(x: 2100, y: 400),
            size: NSSize(width: 66, height: 142),
            visibleFrames: [primary, secondary]
        )

        XCTAssertEqual(origin, NSPoint(x: 2100, y: 400))
    }

    func testStatusPanelPrefersRightSideAndCentersVertically() {
        let origin = DesktopLightLayout.adjacentPanelOrigin(
            panelSize: NSSize(width: 340, height: 500),
            anchorFrame: NSRect(x: 200, y: 300, width: 104, height: 190),
            visibleFrames: [NSRect(x: 0, y: 0, width: 1440, height: 875)]
        )

        XCTAssertEqual(origin, NSPoint(x: 314, y: 145))
    }

    func testStatusPanelFallsBackToLeftNearRightEdge() {
        let origin = DesktopLightLayout.adjacentPanelOrigin(
            panelSize: NSSize(width: 340, height: 500),
            anchorFrame: NSRect(x: 1300, y: 300, width: 104, height: 190),
            visibleFrames: [NSRect(x: 0, y: 0, width: 1440, height: 875)]
        )

        XCTAssertEqual(origin, NSPoint(x: 950, y: 145))
    }
}
