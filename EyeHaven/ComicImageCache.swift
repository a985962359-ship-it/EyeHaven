import UIKit

/// 漫画格磁盘图缓存，避免滑动时反复解码同一文件导致卡顿。
enum ComicImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 48
        c.totalCostLimit = 40 * 1024 * 1024
        return c
    }()

    static func image(at url: URL) -> UIImage? {
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let img = UIImage(contentsOfFile: url.path) else { return nil }
        let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
        cache.setObject(img, forKey: key, cost: max(cost, 1))
        return img
    }
}
