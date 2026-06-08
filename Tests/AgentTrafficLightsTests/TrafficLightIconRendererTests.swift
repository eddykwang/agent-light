import AgentTrafficLightsCore
import XCTest
@testable import AgentTrafficLights

final class TrafficLightIconRendererTests: XCTestCase {
    func testVerticalRendererReturnsImage() {
        let image = TrafficLightIconRenderer.image(status: .working, orientation: .vertical)

        XCTAssertEqual(image.size.width, 22)
        XCTAssertEqual(image.size.height, 22)
        XCTAssertFalse(image.isTemplate)
    }

    func testHorizontalRendererReturnsImage() {
        let image = TrafficLightIconRenderer.image(status: .needsInput, orientation: .horizontal)

        XCTAssertEqual(image.size.width, 28)
        XCTAssertEqual(image.size.height, 22)
        XCTAssertFalse(image.isTemplate)
    }

    func testUnknownStatusUsesNeutralLampColors() throws {
        let statuses: [AgentStatus] = [.failed, .needsInput, .working]

        for lampStatus in statuses {
            let color = TrafficLightIconRenderer.lampColor(
                lampStatus: lampStatus,
                aggregateStatus: .unknown,
                active: false
            ).usingColorSpace(.deviceRGB)

            let rgbColor = try XCTUnwrap(color)
            XCTAssertEqual(rgbColor.redComponent, rgbColor.greenComponent, accuracy: 0.001)
            XCTAssertEqual(rgbColor.greenComponent, rgbColor.blueComponent, accuracy: 0.001)
        }
    }

    func testOperationalStatusesActivateExpectedLamps() {
        XCTAssertTrue(TrafficLightIconRenderer.isActiveLamp(.working, for: .working))
        XCTAssertTrue(TrafficLightIconRenderer.isActiveLamp(.needsInput, for: .needsInput))
        XCTAssertTrue(TrafficLightIconRenderer.isActiveLamp(.failed, for: .failed))

        XCTAssertFalse(TrafficLightIconRenderer.isActiveLamp(.working, for: .idle))
        XCTAssertFalse(TrafficLightIconRenderer.isActiveLamp(.needsInput, for: .working))
        XCTAssertFalse(TrafficLightIconRenderer.isActiveLamp(.failed, for: .unknown))
    }

    func testActiveLampColorsFollowOperationalSemantics() throws {
        let working = try XCTUnwrap(TrafficLightIconRenderer.lampColor(
            lampStatus: .working,
            aggregateStatus: .working,
            active: true
        ).usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(working.greenComponent, working.redComponent)

        let needsInput = try XCTUnwrap(TrafficLightIconRenderer.lampColor(
            lampStatus: .needsInput,
            aggregateStatus: .needsInput,
            active: true
        ).usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(needsInput.redComponent, 0.9)
        XCTAssertGreaterThan(needsInput.greenComponent, 0.6)
        XCTAssertLessThan(needsInput.blueComponent, 0.2)

        let failed = try XCTUnwrap(TrafficLightIconRenderer.lampColor(
            lampStatus: .failed,
            aggregateStatus: .failed,
            active: true
        ).usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(failed.redComponent, failed.greenComponent)
        XCTAssertGreaterThan(failed.redComponent, failed.blueComponent)
    }
}
