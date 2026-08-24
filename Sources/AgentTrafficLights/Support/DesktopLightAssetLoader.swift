import AppKit
import Foundation

enum DesktopLightAsset: String, CaseIterable {
    case housingHorizontal = "housing-horizontal.png"
    case housingVertical = "housing-vertical.png"
    case lampNeutral = "lamp-neutral.png"
}

enum DesktopLightAssetLoader {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(
        _ asset: DesktopLightAsset,
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        sourceRoot: URL? = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> NSImage? {
        for url in candidateURLs(
            for: asset,
            bundleResourceURL: bundleResourceURL,
            sourceRoot: sourceRoot
        ) {
            let key = url.path as NSString
            if let cached = cache.object(forKey: key) {
                return cached
            }
            if let image = NSImage(contentsOf: url) {
                cache.setObject(image, forKey: key)
                return image
            }
        }
        return nil
    }

    static func candidateURLs(
        for asset: DesktopLightAsset,
        bundleResourceURL: URL?,
        sourceRoot: URL?
    ) -> [URL] {
        var urls: [URL] = []
        if let bundleResourceURL {
            urls.append(
                bundleResourceURL
                    .appendingPathComponent("DesktopLightAssets", isDirectory: true)
                    .appendingPathComponent(asset.rawValue)
            )
        }
        if let sourceRoot {
            urls.append(
                sourceRoot
                    .appendingPathComponent("Resources/DesktopLightAssets", isDirectory: true)
                    .appendingPathComponent(asset.rawValue)
            )
        }
        return urls
    }
}
