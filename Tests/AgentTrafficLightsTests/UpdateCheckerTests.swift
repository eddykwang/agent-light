import Foundation
import XCTest
@testable import AgentTrafficLights

final class UpdateCheckerTests: XCTestCase {
    func testCompareVersionsOrdersPatchNumbersNumerically() {
        XCTAssertEqual(UpdateChecker.compareVersions("0.1.10", "0.1.3"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("0.1.3", "0.1.10"), .orderedAscending)
        XCTAssertEqual(UpdateChecker.compareVersions("v0.1.3", "0.1.3"), .orderedSame)
    }

    func testLatestReleaseParsesAvailableUpdate() throws {
        let data = Data("""
        {
          "tag_name": "v0.1.4",
          "html_url": "https://github.com/eddykwang/agent-light/releases/tag/v0.1.4"
        }
        """.utf8)

        let update = try XCTUnwrap(UpdateChecker.parseLatestRelease(data, currentVersion: "0.1.3"))

        XCTAssertEqual(update.version, "0.1.4")
        XCTAssertEqual(update.currentVersion, "0.1.3")
        XCTAssertEqual(update.pageURL.absoluteString, "https://github.com/eddykwang/agent-light/releases/tag/v0.1.4")
    }

    func testLatestReleaseReturnsNilWhenCurrentVersionIsUpToDate() throws {
        let data = Data("""
        {
          "tag_name": "v0.1.3",
          "html_url": "https://github.com/eddykwang/agent-light/releases/tag/v0.1.3"
        }
        """.utf8)

        XCTAssertNil(try UpdateChecker.parseLatestRelease(data, currentVersion: "0.1.3"))
    }
}
