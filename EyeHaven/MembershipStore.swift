import Foundation
import Observation
import StoreKit

/// 订阅商品 ID（须与 App Store Connect / Products.storekit 一致）
enum MembershipProductID {
    static let monthly = "com.eyehaven.app.sub.monthly"
    static let yearly = "com.eyehaven.app.sub.yearly"
    static let all: Set<String> = [monthly, yearly]
}

/// 免费试听额度：目录标题始终可看；整篇可听前若干篇。
enum MembershipFreeQuota {
    /// 知识 / 人物 / 地理 / 安全：每个年龄×书架前 5 篇
    static let perShelf = 5
    /// 故事子目录：每组前 8 篇（多留一点留孩子）
    static let perFairyGroup = 8
}

/// 会员状态与苹果内购。护眼计时/休息/打卡不在这里，永远免费。
@MainActor
@Observable
final class MembershipStore {
    static let shared = MembershipStore()

    private(set) var products: [Product] = []
    private(set) var isMember = false
    private(set) var isLoading = false
    private(set) var statusMessage: String?
    /// 商店里已有可卖商品时才真正限制试听；否则不锁库（避免后台商品未建好时全家听不了）
    private(set) var billingReady = false

    var showPaywall = false

    @ObservationIgnored
    private nonisolated(unsafe) var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { await listenForTransactions() }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == MembershipProductID.monthly }
    }

    var yearlyProduct: Product? {
        products.first { $0.id == MembershipProductID.yearly }
    }

    /// 是否应拦截非免费篇播放
    var shouldEnforce: Bool { billingReady && !isMember }

    func bootstrap() {
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: MembershipProductID.all)
            products = loaded.sorted { $0.price < $1.price }
            billingReady = !loaded.isEmpty
            await refreshEntitlements()
            if loaded.isEmpty {
                statusMessage = "订阅商品还没在苹果后台上架，先都能听。上架后自动按免费额度试听。"
            } else {
                statusMessage = nil
            }
        } catch {
            billingReady = false
            statusMessage = "暂时连不上商店，先都能听。"
        }
    }

    func canPlay(_ story: BedtimeStory) -> Bool {
        if isMember { return true }
        if !billingReady { return true }
        return isFreeQuota(story)
    }

    func isFreeQuota(_ story: BedtimeStory) -> Bool {
        let list = quotaList(for: story)
        guard let idx = list.firstIndex(where: { $0.id == story.id }) else { return false }
        let limit = story.shelfId == "fairy" ? MembershipFreeQuota.perFairyGroup : MembershipFreeQuota.perShelf
        return idx < limit
    }

    /// 目录上显示「免费试听」角标
    func showsFreeBadge(for story: BedtimeStory) -> Bool {
        !isMember && isFreeQuota(story)
    }

    /// 目录上显示锁（仅在真正收费时）
    func showsLock(for story: BedtimeStory) -> Bool {
        shouldEnforce && !isFreeQuota(story)
    }

    func requestPlay(_ story: BedtimeStory) -> Bool {
        if canPlay(story) { return true }
        showPaywall = true
        return false
    }

    func purchase(_ product: Product) async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                if isMember {
                    showPaywall = false
                    statusMessage = "会员已开通。护眼功能仍一直免费。"
                }
            case .userCancelled:
                break
            case .pending:
                statusMessage = "购买待确认，请稍后再看会员状态。"
            @unknown default:
                break
            }
        } catch {
            statusMessage = "购买没成功，请稍后重试。"
        }
    }

    func restore() async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusMessage = isMember ? "已恢复会员。" : "没有找到可恢复的会员。"
        } catch {
            statusMessage = "恢复失败，请检查网络后重试。"
        }
    }

    // MARK: - private

    private func quotaList(for story: BedtimeStory) -> [BedtimeStory] {
        let catalog = BedtimeCatalogStore.shared
        if story.shelfId == "fairy", let groupId = story.fairyGroupId {
            return catalog.stories(ageId: story.ageId, shelfId: story.shelfId, groupId: groupId)
        }
        return catalog.stories(ageId: story.ageId, shelfId: story.shelfId)
    }

    private func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if MembershipProductID.all.contains(transaction.productID),
               transaction.revocationDate == nil
            {
                active = true
                break
            }
        }
        isMember = active
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if let transaction = try? checkVerified(result) {
                await transaction.finish()
                await refreshEntitlements()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
