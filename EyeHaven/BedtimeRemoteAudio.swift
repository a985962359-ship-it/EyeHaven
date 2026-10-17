import Foundation

/// 睡前语音：云端地址 + 本机缓存。大文件不进安装包。
enum BedtimeRemoteAudio {
    /// 在 Info.plist 的 BedtimeAudioBaseURL 填写，末尾保留 /
    /// GitHub 试用：https://raw.githubusercontent.com/账号/仓库/分支/bedtime-audio/
    /// 腾讯云 COS：https://桶.cos.地域.myqcloud.com/bedtime-audio/
    private static let plistKey = "BedtimeAudioBaseURL"

    /// 默认走 GitHub audio-cdn 分支（试用）；正式上架可再改 COS
    private static let fallbackBase =
        "https://raw.githubusercontent.com/a985962359-ship-it/EyeHaven/audio-cdn/bedtime-audio/"

    private static let cacheFolderName = "BedtimeAudioCache"

    private static var bodyIds: Set<String> = []
    private static var titleIds: Set<String> = []
    private static var didLoadManifest = false

    static var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let u = URL(string: trimmed) {
                return u
            }
        }
        return URL(string: fallbackBase)!
    }

    static var isConfigured: Bool {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String else {
            return false
        }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && !t.contains("placeholder")
    }

    static func loadManifestIfNeeded() {
        guard !didLoadManifest else { return }
        didLoadManifest = true
        guard let url = Bundle.main.url(forResource: "BedtimeAudioManifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        if let bodies = obj["bodies"] as? [String] {
            bodyIds = Set(bodies)
        }
        if let titles = obj["titles"] as? [String] {
            titleIds = Set(titles)
        }
    }

    static func hasBody(_ storyId: String) -> Bool {
        loadManifestIfNeeded()
        if bundleBodyURL(storyId) != nil { return true }
        if FileManager.default.fileExists(atPath: cacheBodyURL(storyId).path) { return true }
        return bodyIds.contains(storyId)
    }

    static func hasTitle(_ storyId: String) -> Bool {
        loadManifestIfNeeded()
        if bundleTitleURL(storyId) != nil { return true }
        if FileManager.default.fileExists(atPath: cacheTitleURL(storyId).path) { return true }
        return titleIds.contains(storyId)
    }

    /// 优先：安装包 → 缓存 → 云端 URL（可边下边播）
    static func resolveBodyURL(_ storyId: String) -> URL? {
        loadManifestIfNeeded()
        if let u = bundleBodyURL(storyId) { return u }
        let cached = cacheBodyURL(storyId)
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        guard bodyIds.contains(storyId) else { return nil }
        return baseURL.appendingPathComponent("\(storyId).mp3")
    }

    static func resolveTitleURL(_ storyId: String) -> URL? {
        loadManifestIfNeeded()
        if let u = bundleTitleURL(storyId) { return u }
        let cached = cacheTitleURL(storyId)
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        guard titleIds.contains(storyId) else { return nil }
        return baseURL.appendingPathComponent("Titles/\(storyId).mp3")
    }

    /// 播放时顺带缓存，下次离线也能听
    static func prefetchToCache(remote url: URL, storyId: String, isTitle: Bool) {
        guard url.scheme == "http" || url.scheme == "https" else { return }
        let dest = isTitle ? cacheTitleURL(storyId) : cacheBodyURL(storyId)
        if FileManager.default.fileExists(atPath: dest.path) { return }
        Task.detached(priority: .utility) {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode)
                else { return }
                try FileManager.default.createDirectory(
                    at: dest.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: dest, options: .atomic)
            } catch {
                // 缓存失败不影响当前流式播放
            }
        }
    }

    // MARK: - paths

    private static func bundleBodyURL(_ storyId: String) -> URL? {
        Bundle.main.url(forResource: storyId, withExtension: "mp3", subdirectory: "BedtimeAudio")
            ?? Bundle.main.url(forResource: storyId, withExtension: "mp3", subdirectory: "BedtimeAudioBundle")
            ?? Bundle.main.url(forResource: storyId, withExtension: "mp3")
    }

    private static func bundleTitleURL(_ storyId: String) -> URL? {
        Bundle.main.url(forResource: storyId, withExtension: "mp3", subdirectory: "BedtimeAudio/Titles")
            ?? Bundle.main.url(forResource: storyId, withExtension: "mp3", subdirectory: "BedtimeAudioBundle/Titles")
            ?? Bundle.main.url(forResource: storyId, withExtension: "mp3", subdirectory: "Titles")
    }

    private static var cacheRoot: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(cacheFolderName, isDirectory: true)
    }

    private static func cacheBodyURL(_ storyId: String) -> URL {
        cacheRoot.appendingPathComponent("\(storyId).mp3")
    }

    private static func cacheTitleURL(_ storyId: String) -> URL {
        cacheRoot.appendingPathComponent("Titles/\(storyId).mp3")
    }
}
