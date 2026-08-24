import AppKit
import XCTest
@testable import AgentTrafficLights

final class DesktopLightAssetLoaderTests: XCTestCase {
    func testSourceAssetsLoadWithExpectedPixelsAndTransparency() throws {
        let expectations: [(DesktopLightAsset, Int, Int)] = [
            (.housingHorizontal, 1008, 400),
            (.housingVertical, 400, 1008),
            (.lampNeutral, 272, 272)
        ]

        for (asset, expectedWidth, expectedHeight) in expectations {
            let url = sourceAssetsURL.appendingPathComponent(asset.rawValue)
            let data = try Data(contentsOf: url)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))

            XCTAssertEqual(bitmap.pixelsWide, expectedWidth)
            XCTAssertEqual(bitmap.pixelsHigh, expectedHeight)
            XCTAssertTrue(bitmap.hasAlpha)
            XCTAssertEqual(bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1, 0, accuracy: 0.01)
            XCTAssertGreaterThan(
                bitmap.colorAt(x: expectedWidth / 2, y: expectedHeight / 2)?.alphaComponent ?? 0,
                0.99
            )
        }
    }

    func testLoaderFindsSourceAssetsWhenBundleCopyIsUnavailable() {
        for asset in DesktopLightAsset.allCases {
            XCTAssertNotNil(DesktopLightAssetLoader.image(
                asset,
                bundleResourceURL: nil,
                sourceRoot: repositoryRoot
            ))
        }
    }

    func testBundleCandidatePrecedesSourceCandidate() {
        let bundleRoot = URL(fileURLWithPath: "/tmp/example-bundle-resources")
        let sourceRoot = URL(fileURLWithPath: "/tmp/example-source-root")
        let candidates = DesktopLightAssetLoader.candidateURLs(
            for: .lampNeutral,
            bundleResourceURL: bundleRoot,
            sourceRoot: sourceRoot
        )

        XCTAssertEqual(
            candidates,
            [
                bundleRoot.appendingPathComponent("DesktopLightAssets/lamp-neutral.png"),
                sourceRoot.appendingPathComponent("Resources/DesktopLightAssets/lamp-neutral.png")
            ]
        )
    }

    private var sourceAssetsURL: URL {
        repositoryRoot.appendingPathComponent("Resources/DesktopLightAssets", isDirectory: true)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
