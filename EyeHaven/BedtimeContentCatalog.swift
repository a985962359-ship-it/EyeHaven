import Foundation
import Observation

/// 远程/本地「内容目录」：分类名、子目录、篇目与正文都在 JSON 里，程序只负责展示与刷新。
/// 不要接到休息计时、锁屏或通知。

struct CatalogAgeInfo: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var title: String
    var ageRange: String
    var hint: String
}

struct CatalogShelfInfo: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var title: String
    var badge: String
    var blurb: String
    var footer: String
    var coverImage: String?
    var usesFairyGroups: Bool
    var sort: Int

    var badgeLines: String { badge }
    var coverTitle: String { badge }
}

struct CatalogFairyGroupInfo: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var title: String
    var originNote: String
    var badge: String
    /// Assets 里的书皮图名；没有则显示黄底徽章
    var coverImage: String?
}

struct BedtimeContentDocument: Codable, Sendable {
    var version: Int
    var updatedAt: String?
    var ages: [CatalogAgeInfo]
    var shelves: [CatalogShelfInfo]
    var fairyGroups: [CatalogFairyGroupInfo]
    var stories: [CatalogStoryItem]
}

struct CatalogStoryItem: Codable, Hashable, Sendable {
    var id: String
    var age: String
    var shelf: String
    var title: String
    var text: String
    var group: String?
}

@MainActor
@Observable
final class BedtimeCatalogStore {
    static let shared = BedtimeCatalogStore()

    private static let cacheName = "BedtimeContentCatalog.cache.json"
    private static let plistKey = "BedtimeCatalogURL"
    private static let fallbackURL =
        "https://raw.githubusercontent.com/a985962359-ship-it/EyeHaven/audio-cdn/bedtime-catalog/content-catalog.json"

    private(set) var ages: [CatalogAgeInfo] = []
    private(set) var shelves: [CatalogShelfInfo] = []
    private(set) var fairyGroups: [CatalogFairyGroupInfo] = []
    private(set) var stories: [BedtimeStory] = []
    private(set) var version: Int = 0
    private(set) var updatedAt: String?
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    private(set) var lastRefreshAt: Date?

    private var didBootstrap = false
    private var bootstrapTask: Task<Void, Never>?
    /// id → 故事，避免每次线性扫 500+ 篇
    private var storyById: [String: BedtimeStory] = [:]
    /// "age|shelf" → 该架篇目
    private var storiesByAgeShelf: [String: [BedtimeStory]] = [:]
    /// "age|shelf|group" → 故事子目录篇目
    private var storiesByAgeShelfGroup: [String: [BedtimeStory]] = [:]

    var catalogURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: Self.plistKey) as? String {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, let u = URL(string: t) { return u }
        }
        return URL(string: Self.fallbackURL)!
    }

    private init() {
        // 大目录 JSON 放到后台解码，避免 Device Hub / iPhone 启动卡几秒
        bootstrapTask = Task { await bootstrapFromDisk() }
    }

    func ensureLoaded() {
        guard !didBootstrap else { return }
        if bootstrapTask == nil {
            bootstrapTask = Task { await bootstrapFromDisk() }
        }
    }

    /// 打开 App / 进书架时调用：先显示本地，再拉网上最新目录。
    /// - Parameter showSpinner: 下拉刷新才转圈；后台静默更新不挡界面，避免 iPhone 卡住。
    func refreshIfNeeded(force: Bool = false, showSpinner: Bool = false) {
        Task { await refresh(force: force, showSpinner: showSpinner || force) }
    }

    func refresh(force: Bool = false, showSpinner: Bool = false) async {
        ensureLoaded()
        if isRefreshing { return }
        // 自动刷新：10 分钟内不重复拉；手动下拉仍可 force
        if !force, let last = lastRefreshAt, Date().timeIntervalSince(last) < 600 {
            return
        }
        if showSpinner { isRefreshing = true }
        lastError = nil
        defer { if showSpinner { isRefreshing = false } }

        do {
            var request = URLRequest(url: catalogURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 45
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            // 解码 + 建索引都在后台，主线程只赋值
            let prepared = try await Task.detached(priority: .userInitiated) {
                let doc = try JSONDecoder().decode(BedtimeContentDocument.self, from: data)
                return try Self.prepare(document: doc)
            }.value
            // 网上目录更旧时不覆盖本机，避免旧缓存把新故事盖掉
            if !stories.isEmpty,
               !Self.catalogIsNewer(prepared.version, prepared.updatedAt, than: version, updatedAt: updatedAt) {
                lastRefreshAt = Date()
                return
            }
            applyPrepared(prepared)
            if let cached = cacheURL() {
                try? FileManager.default.createDirectory(
                    at: cached.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? data.write(to: cached, options: .atomic)
            }
            lastRefreshAt = Date()
        } catch {
            if showSpinner {
                lastError = "目录暂时没更新，先用本机已有内容。"
            }
            lastRefreshAt = Date()
        }
    }

    func age(id: String) -> CatalogAgeInfo? {
        ages.first { $0.id == id }
    }

    func shelf(id: String) -> CatalogShelfInfo? {
        shelves.first { $0.id == id }
    }

    func fairyGroup(id: String) -> CatalogFairyGroupInfo? {
        fairyGroups.first { $0.id == id }
    }

    func stories(ageId: String, shelfId: String) -> [BedtimeStory] {
        storiesByAgeShelf[Self.ageShelfKey(ageId, shelfId)] ?? []
    }

    func stories(ageId: String, shelfId: String, groupId: String) -> [BedtimeStory] {
        storiesByAgeShelfGroup[Self.ageShelfGroupKey(ageId, shelfId, groupId)] ?? []
    }

    func playQueue(for story: BedtimeStory) -> [BedtimeStory] {
        if let groupId = story.fairyGroupId,
           shelf(id: story.shelfId)?.usesFairyGroups == true
        {
            return stories(ageId: story.ageId, shelfId: story.shelfId, groupId: groupId)
        }
        return stories(ageId: story.ageId, shelfId: story.shelfId)
    }

    func story(id: String) -> BedtimeStory? {
        storyById[id]
    }

    // MARK: - load

    /// 磁盘目录在后台读+解码，主线程只接收结果（修 Device Hub 装到 iPhone 卡几秒）
    private func bootstrapFromDisk() async {
        guard !didBootstrap else { return }
        let cache = cacheURL()
        let bundleURL = Bundle.main.url(forResource: "BedtimeContentCatalog", withExtension: "json")
        let legacyURL = Bundle.main.url(forResource: "BedtimeCatalog", withExtension: "json")

        let prepared = await Task.detached(priority: .userInitiated) { () -> PreparedCatalog? in
            func load(_ url: URL?) -> PreparedCatalog? {
                guard let url,
                      let data = try? Data(contentsOf: url),
                      let doc = try? JSONDecoder().decode(BedtimeContentDocument.self, from: data),
                      let ready = try? Self.prepare(document: doc)
                else { return nil }
                return ready
            }
            let cached = load(cache)
            let bundled = load(bundleURL)
            switch (cached, bundled) {
            case let (c?, b?):
                return Self.catalogIsNewer(b.version, b.updatedAt, than: c.version, updatedAt: c.updatedAt) ? b : c
            case let (c?, nil):
                return c
            case let (nil, b?):
                return b
            default:
                return nil
            }
        }.value

        if let prepared {
            applyPrepared(prepared)
            didBootstrap = true
            return
        }
        // 最后兜底：旧版 BedtimeCatalog.json
        await loadLegacyCatalogAsync(legacyURL: legacyURL)
        didBootstrap = true
    }

    private struct PreparedCatalog: Sendable {
        var version: Int
        var updatedAt: String?
        var ages: [CatalogAgeInfo]
        var shelves: [CatalogShelfInfo]
        var fairyGroups: [CatalogFairyGroupInfo]
        var stories: [BedtimeStory]
        var storyById: [String: BedtimeStory]
        var storiesByAgeShelf: [String: [BedtimeStory]]
        var storiesByAgeShelfGroup: [String: [BedtimeStory]]
    }

    /// 版本更大，或版本相同但日期更新，才算更新的目录。
    nonisolated private static func catalogIsNewer(
        _ version: Int,
        _ updatedAt: String?,
        than otherVersion: Int,
        updatedAt otherUpdatedAt: String?
    ) -> Bool {
        if version != otherVersion { return version > otherVersion }
        return (updatedAt ?? "") > (otherUpdatedAt ?? "")
    }

    nonisolated private static func prepare(document doc: BedtimeContentDocument) throws -> PreparedCatalog {
        guard !doc.ages.isEmpty, !doc.shelves.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        let ageMap = Dictionary(uniqueKeysWithValues: doc.ages.map { ($0.id, $0) })
        let shelfMap = Dictionary(uniqueKeysWithValues: doc.shelves.map { ($0.id, $0) })
        let mapped: [BedtimeStory] = doc.stories.map { item in
            let ageId = normalizeAge(item.age)
            let ageInfo = ageMap[ageId]
            let shelfInfo = shelfMap[item.shelf]
            return BedtimeStory(
                id: item.id,
                ageId: ageId,
                shelfId: item.shelf,
                title: item.title,
                text: item.text,
                fairyGroupId: item.group,
                ageTitle: ageInfo?.title ?? ageId,
                shelfTitle: shelfInfo?.title ?? item.shelf,
                ageRangeText: ageInfo?.ageRange ?? ""
            )
        }
        var byShelf: [String: [BedtimeStory]] = [:]
        var byGroup: [String: [BedtimeStory]] = [:]
        byShelf.reserveCapacity(16)
        byGroup.reserveCapacity(32)
        for story in mapped {
            let sk = ageShelfKey(story.ageId, story.shelfId)
            byShelf[sk, default: []].append(story)
            if let group = story.fairyGroupId {
                let gk = ageShelfGroupKey(story.ageId, story.shelfId, group)
                byGroup[gk, default: []].append(story)
            }
        }
        return PreparedCatalog(
            version: doc.version,
            updatedAt: doc.updatedAt,
            ages: doc.ages,
            shelves: doc.shelves.sorted { $0.sort < $1.sort },
            fairyGroups: doc.fairyGroups,
            stories: mapped,
            storyById: Dictionary(uniqueKeysWithValues: mapped.map { ($0.id, $0) }),
            storiesByAgeShelf: byShelf,
            storiesByAgeShelfGroup: byGroup
        )
    }

    private func applyPrepared(_ prepared: PreparedCatalog) {
        version = prepared.version
        updatedAt = prepared.updatedAt
        ages = prepared.ages
        shelves = prepared.shelves
        fairyGroups = prepared.fairyGroups
        stories = prepared.stories
        storyById = prepared.storyById
        storiesByAgeShelf = prepared.storiesByAgeShelf
        storiesByAgeShelfGroup = prepared.storiesByAgeShelfGroup
    }

    nonisolated private static func ageShelfKey(_ ageId: String, _ shelfId: String) -> String {
        "\(ageId)|\(shelfId)"
    }

    nonisolated private static func ageShelfGroupKey(_ ageId: String, _ shelfId: String, _ groupId: String) -> String {
        "\(ageId)|\(shelfId)|\(groupId)"
    }

    private func loadLegacyCatalogAsync(legacyURL: URL?) async {
        let agesSeed: [CatalogAgeInfo] = [
            .init(id: "child", title: "儿童类", ageRange: "3–10岁", hint: ""),
            .init(id: "youth", title: "少年类", ageRange: "11–15岁", hint: ""),
        ]
        let shelvesSeed: [CatalogShelfInfo] = [
            .init(id: "knowledge", title: "光光讲知识", badge: "知识", blurb: "", footer: "", coverImage: "ShelfKnowledge", usesFairyGroups: false, sort: 1),
            .init(id: "fairy", title: "光光睡前小故事", badge: "故事", blurb: "", footer: "", coverImage: "ShelfFairy", usesFairyGroups: true, sort: 2),
            .init(id: "biography", title: "光光讲人物", badge: "人物", blurb: "", footer: "", coverImage: "ShelfBiography", usesFairyGroups: false, sort: 3),
            .init(id: "treasure", title: "光光去寻宝", badge: "地理", blurb: "", footer: "", coverImage: "ShelfGeography", usesFairyGroups: false, sort: 4),
            .init(id: "safety", title: "光光安全小剧场", badge: "安全", blurb: "", footer: "", coverImage: "ShelfSafety", usesFairyGroups: false, sort: 5),
        ]
        let groupsSeed: [CatalogFairyGroupInfo] = [
            .init(id: "cn_myth_legend", title: "中国 · 神话·传说", originNote: "神话、民间与戏曲传说", badge: "神话", coverImage: "ShelfFairyMyth"),
            .init(id: "cn_fable_story", title: "中国 · 寓言·故事", originNote: "成语寓言、史传典故", badge: "寓言", coverImage: "ShelfFairyFable"),
            .init(id: "foreign", title: "国外 · 寓言·童话·传说", originNote: "伊索、格林、安徒生、世界民间", badge: "国外", coverImage: "ShelfFairyForeign"),
            .init(id: "original", title: "原创 · 思辨小故事", originNote: "新写寓言，非公版改编", badge: "原创", coverImage: "ShelfFairyOriginal"),
        ]
        guard let legacyURL else {
            ages = agesSeed
            shelves = shelvesSeed
            fairyGroups = groupsSeed
            return
        }
        let prepared = await Task.detached(priority: .userInitiated) { () -> PreparedCatalog? in
            guard let data = try? Data(contentsOf: legacyURL),
                  let items = try? JSONDecoder().decode([CatalogStoryItem].self, from: data)
            else { return nil }
            let doc = BedtimeContentDocument(
                version: 0,
                updatedAt: nil,
                ages: agesSeed,
                shelves: shelvesSeed,
                fairyGroups: groupsSeed,
                stories: items
            )
            return try? Self.prepare(document: doc)
        }.value
        if let prepared {
            applyPrepared(prepared)
        } else {
            ages = agesSeed
            shelves = shelvesSeed
            fairyGroups = groupsSeed
        }
    }

    nonisolated private static func normalizeAge(_ raw: String) -> String {
        switch raw {
        case "kindergarten", "primary", "child": return "child"
        case "junior", "youth": return "youth"
        default: return raw
        }
    }

    private func cacheURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("EyeHaven", isDirectory: true)
            .appendingPathComponent(Self.cacheName)
    }
}
