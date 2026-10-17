import SwiftUI
import UIKit

/// 故事书架。不要在这里引用 RestSession、RestStoryPlayer 或发通知。
struct TipsView: View {
    @Environment(BedtimeCatalogStore.self) private var catalog
    @Environment(MembershipStore.self) private var membership
    @State private var ageId: String = Self.savedAgeId()
    @State private var audio = BedtimeAudioPlayer.shared

    private var ages: [CatalogAgeInfo] { catalog.ages }
    private var currentAge: CatalogAgeInfo? { catalog.age(id: ageId) ?? ages.first }

    var body: some View {
        NavigationStack {
            Group {
                if HavenLayout.isPad {
                    padHome
                } else {
                    phoneHome
                }
            }
            .background {
                CatalogLeafBackground()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                catalog.ensureLoaded()
                audio.migrateGlobalLastIfNeeded()
                if ages.contains(where: { $0.id == ageId }) == false, let first = ages.first {
                    ageId = first.id
                }
                // 静默刷新，不转圈；App 启动已刷新过则 10 分钟内会直接跳过
                catalog.refreshIfNeeded(showSpinner: false)
            }
            .onChange(of: ageId) { _, newId in
                UserDefaults.standard.set(newId, forKey: Self.ageKey)
            }
        }
    }

    /// iPad 方案 A：左书架目录，右预览可循环滑
    private var padHome: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                agePicker
                ScrollView {
                    shelfListColumn
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 28)
                }
                .refreshable { await catalog.refresh(force: true, showSpinner: true) }
            }
            .frame(maxWidth: 420)

            GuangguangBanner(fillsAvailableHeight: true)
                .padding(.trailing, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var phoneHome: some View {
        VStack(spacing: 0) {
            agePicker
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GuangguangBanner(fillsAvailableHeight: false)
                    shelfListColumn
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
            .refreshable { await catalog.refresh(force: true, showSpinner: true) }
        }
    }

    @ViewBuilder
    private var agePicker: some View {
        if ages.count > 1 {
            Picker("分类", selection: $ageId) {
                ForEach(ages) { item in
                    Text(item.title).tag(item.id)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, HavenLayout.isPad ? 20 : 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Palette.foam.opacity(0.55).ignoresSafeArea(edges: .top))
        }
    }

    private var shelfListColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("光光讲知识")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.pine)
                Text("先选年龄，再点一本书。下拉可刷新目录。")
                    .font(.caption)
                    .foregroundStyle(Palette.pine.opacity(0.6))
            }
            .padding(.bottom, 2)

            if catalog.isRefreshing {
                Label("正在更新内容目录…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.moss)
            } else if let err = catalog.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Palette.pine.opacity(0.65))
            }

            ForEach(catalog.shelves) { shelf in
                let stories = catalog.stories(ageId: ageId, shelfId: shelf.id)
                let resume = audio.resumeStory(ageId: ageId, shelfId: shelf.id)
                ZStack(alignment: .topLeading) {
                    NavigationLink {
                        StoryCatalogPage(ageId: ageId, shelfId: shelf.id)
                    } label: {
                        bookCard(
                            badge: shelf.badge,
                            title: shelf.title,
                            meta: "\(stories.count) 篇 · \(currentAge?.title ?? "") \(currentAge?.ageRange ?? "")",
                            line: shelf.blurb,
                            coverImage: shelf.coverImage,
                            coverTitle: shelf.coverTitle,
                            resumeTitle: resume?.title,
                            reservesContinueSlot: resume != nil
                        )
                    }
                    .buttonStyle(ShelfCardButtonStyle())

                    if resume != nil {
                        Button {
                            guard let story = audio.resumeStory(ageId: ageId, shelfId: shelf.id)
                            else { return }
                            guard membership.requestPlay(story) else { return }
                            audio.continueShelf(ageId: ageId, shelfId: shelf.id)
                        } label: {
                            Label("继续播放", systemImage: "play.fill")
                                .font(.caption2.weight(.bold))
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(Palette.foam)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(width: 72)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Palette.moss))
                        }
                        .buttonStyle(.plain)
                        // 书本图下方：上内边距 16 + 封面高 100 + 间距 8
                        .padding(.leading, 16)
                        .padding(.top, 16 + 100 + 8)
                        .accessibilityLabel("继续播放\(shelf.title)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bookCard(
        badge: String,
        title: String,
        meta: String,
        line: String,
        coverImage: String? = nil,
        coverTitle: String? = nil,
        resumeTitle: String? = nil,
        reservesContinueSlot: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // 左列：书本图；有进度时下方留出「继续播放」位置
            VStack(spacing: 8) {
                Group {
                    if let coverImage, let coverTitle {
                        // 底图只作书皮；字用系统字体叠上，小图标也清晰
                        Image(coverImage)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFill()
                            .frame(width: 72, height: 100)
                            .overlay {
                                Text(coverTitle)
                                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Palette.pine)
                                    .shadow(color: .white.opacity(0.95), radius: 1.2, y: 0)
                                    .shadow(color: .white.opacity(0.7), radius: 0, x: 0.5, y: 0.5)
                                    .padding(.top, 12)
                                    .frame(maxHeight: .infinity, alignment: .top)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: Palette.pine.opacity(0.18), radius: 4, y: 2)
                            .accessibilityLabel(coverTitle)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Palette.gold.opacity(0.9))
                            .frame(width: 72, height: 100)
                            .overlay {
                                Text(badge)
                                    .font(.caption.weight(.heavy))
                                    .foregroundStyle(Palette.pine)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(2)
                                    .padding(.horizontal, 4)
                            }
                    }
                }

                if reservesContinueSlot {
                    Color.clear
                        .frame(width: 72, height: 30)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.dusk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(meta)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.gold)
                if let resumeTitle {
                    Text("上次：\(resumeTitle)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.moss)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(Palette.pine.opacity(0.75))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.sage)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.foam.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Palette.sage.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: Palette.pine.opacity(0.07), radius: 8, y: 3)
        )
    }

    private static let ageKey = "bedtime.ageId"

    private static func savedAgeId() -> String {
        if let raw = UserDefaults.standard.string(forKey: ageKey), !raw.isEmpty {
            // 新键：child / youth
            if raw == "child" || raw == "youth" { return raw }
            // 旧版本中文标签迁移
            switch raw {
            case "儿童类", "幼儿园", "小学", "3-5岁", "6-8岁", "3–6岁", "7–12岁": return "child"
            case "少年类", "初中", "9-16岁", "9-12岁", "13–15岁": return "youth"
            default: break
            }
        }
        // 更旧的 bedtime.age
        if let legacy = UserDefaults.standard.string(forKey: "bedtime.age") {
            if let age = BedtimeAge(rawValue: legacy) { return age.catalogKey }
            switch legacy {
            case "幼儿园", "小学", "3-5岁", "6-8岁", "3–6岁", "7–12岁": return "child"
            case "初中", "9-16岁", "9-12岁", "13–15岁": return "youth"
            default: break
            }
        }
        return "child"
    }
}

struct StoryCatalogPage: View {
    var ageId: String
    var shelfId: String
    @Environment(BedtimeCatalogStore.self) private var catalog
    @State private var selected: BedtimeStory?
    @State private var previewStory: BedtimeStory?

    private var shelf: CatalogShelfInfo? { catalog.shelf(id: shelfId) }
    private var age: CatalogAgeInfo? { catalog.age(id: ageId) }
    private var stories: [BedtimeStory] { catalog.stories(ageId: ageId, shelfId: shelfId) }

    var body: some View {
        Group {
            if shelf?.usesFairyGroups == true {
                fairyGroupList
            } else {
                CatalogStoryBrowser(
                    metaLine: "共 \(stories.count) 篇 · \(age?.title ?? "")（\(age?.ageRange ?? "")）",
                    footer: shelf?.footer ?? "",
                    stories: stories,
                    selected: $selected,
                    previewStory: $previewStory
                )
            }
        }
        .background {
            CatalogLeafBackground()
        }
        .navigationTitle(shelf?.title ?? "故事")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BedtimeNowPlayingButton(currentStory: previewStory, queue: stories)
            }
        }
        .navigationDestination(item: $selected) { story in
            BedtimeStoryPage(story: story)
        }
    }

    /// 睡前小故事：先选带来历说明的子目录
    private var fairyGroupList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("先选分类 · \(age?.title ?? "")（\(age?.ageRange ?? "")）")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.gold)

                ForEach(catalog.fairyGroups) { group in
                    let count = catalog.stories(ageId: ageId, shelfId: shelfId, groupId: group.id).count
                    NavigationLink {
                        FairyGroupCatalogPage(ageId: ageId, shelfId: shelfId, groupId: group.id)
                    } label: {
                        fairyGroupCard(group: group, count: count)
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0)
                    .opacity(count == 0 ? 0.45 : 1)
                }

                Text("分类名后面是内容来历，方便查找。公版只借情节核，句子新写。")
                    .font(.caption)
                    .foregroundStyle(Palette.pine.opacity(0.55))
                    .padding(.top, 8)
            }
            .padding(HavenLayout.isPad ? 28 : 16)
            .frame(maxWidth: HavenLayout.isPad ? 720 : HavenLayout.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fairyGroupCard(group: CatalogFairyGroupInfo, count: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let cover = group.coverImage, UIImage(named: cover) != nil {
                    Image(cover)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: 56, height: 78)
                        .overlay {
                            Text(group.badge)
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(Palette.pine)
                                .shadow(color: .white.opacity(0.95), radius: 1.2, y: 0)
                                .shadow(color: .white.opacity(0.7), radius: 0, x: 0.5, y: 0.5)
                                .padding(.top, 8)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: Palette.pine.opacity(0.2), radius: 3, y: 1)
                        .accessibilityLabel(group.badge)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Palette.gold.opacity(0.9))
                        .frame(width: 56, height: 78)
                        .overlay {
                            Text(group.badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Palette.pine)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                        }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(group.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.dusk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(group.originNote)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.gold)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(count) 篇")
                    .font(.caption)
                    .foregroundStyle(Palette.pine.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.foam.opacity(0.95))
        )
    }

}

/// 睡前小故事的某一个子目录
struct FairyGroupCatalogPage: View {
    var ageId: String
    var shelfId: String
    var groupId: String
    @Environment(BedtimeCatalogStore.self) private var catalog
    @State private var selected: BedtimeStory?
    @State private var previewStory: BedtimeStory?

    private var group: CatalogFairyGroupInfo? { catalog.fairyGroup(id: groupId) }
    private var stories: [BedtimeStory] {
        catalog.stories(ageId: ageId, shelfId: shelfId, groupId: groupId)
    }

    var body: some View {
        CatalogStoryBrowser(
            metaLine: "\(group?.originNote ?? "") · 共 \(stories.count) 篇",
            footer: "本类来历：\(group?.originNote ?? "")。公版只借情节核，句子新写。",
            stories: stories,
            selected: $selected,
            previewStory: $previewStory
        )
        .background {
            CatalogLeafBackground()
        }
        .navigationTitle(group?.title ?? "故事")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BedtimeNowPlayingButton(currentStory: previewStory, queue: stories)
            }
        }
        .navigationDestination(item: $selected) { story in
            BedtimeStoryPage(story: story)
        }
    }
}

/// iPad：左目录 + 右漫画可滑；iPhone：整宽列表 + 顶上小光光。
private struct CatalogStoryBrowser: View {
    var metaLine: String
    var footer: String
    var stories: [BedtimeStory]
    @Binding var selected: BedtimeStory?
    @Binding var previewStory: BedtimeStory?

    @Environment(MembershipStore.self) private var membership
    @State private var audio = BedtimeAudioPlayer.shared
    @State private var comicPage = 0

    var body: some View {
        @Bindable var membership = membership
        Group {
            if HavenLayout.isPad {
                padSplit
            } else {
                phoneList
            }
        }
        .onAppear { ensurePreview() }
        .onChange(of: stories.map(\.id)) { _, _ in ensurePreview() }
        .onChange(of: previewStory?.id) { _, _ in comicPage = 0 }
        .onChange(of: audio.playingId) { _, newId in
            // 自动连播到下一篇时，右边预览跟着切
            guard let newId,
                  let match = stories.first(where: { $0.id == newId })
            else { return }
            if previewStory?.id != match.id {
                previewStory = match
            }
        }
        .sheet(isPresented: $membership.showPaywall) {
            MembershipPaywallSheet()
                .environment(membership)
        }
    }

    private var padSplit: some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
                listColumn(showHero: false)
                    .padding(.leading, 24)
                    .padding(.trailing, 4)
                    .padding(.vertical, 16)
            }
            .frame(maxWidth: 420)

            catalogComicPreview
                .padding(.trailing, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var phoneList: some View {
        ScrollView {
            listColumn(showHero: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    private func listColumn(showHero: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showHero {
                phoneHero
            }

            Text(metaLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.gold)

            ForEach(Array(stories.enumerated()), id: \.element.id) { index, story in
                let isPreview = previewStory?.id == story.id
                catalogRow(
                    index: index + 1,
                    story: story,
                    isPlaying: audio.playingId == story.id && audio.isPlaying,
                    isCurrent: audio.playingId == story.id,
                    isPreviewSelected: isPreview,
                    hasAudio: audio.hasAudio(for: story.id),
                    isLocked: membership.showsLock(for: story),
                    isFreeBadge: membership.showsFreeBadge(for: story),
                    onSelect: {
                        // 目录标题都能看；正文页也可进，播放才按会员限制
                        if HavenLayout.isPad {
                            previewStory = story
                        } else {
                            selected = story
                        }
                    },
                    onPlay: {
                        previewStory = story
                        guard membership.requestPlay(story) else { return }
                        audio.toggle(story, queue: stories)
                    }
                )
            }

            if !footer.isEmpty {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(Palette.pine.opacity(0.55))
                    .padding(.top, 8)
            }

            Label("向下探索更多知识", systemImage: "leaf.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.moss.opacity(0.85))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var phoneHero: some View {
        HStack(spacing: 12) {
            GuangguangTalking(talking: audio.isPlaying, size: 88)
            Text("选一篇，我陪你听")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.pine)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.foam.opacity(0.95))
                )
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.foam.opacity(0.88))
        )
    }

    @ViewBuilder
    private var catalogComicPreview: some View {
        let urls = previewStory.map { BedtimeComics.panelURLs(for: $0.id) } ?? []
        VStack(spacing: 10) {
            if let story = previewStory {
                Text(story.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Palette.pine)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if urls.isEmpty {
                    // 纯文章：上下只滚动正文，不换篇（换篇用左边目录）
                    ScrollView {
                        Text(story.text)
                            .font(.title3)
                            .foregroundStyle(Palette.dusk)
                            .lineSpacing(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    Text("上下拉看全文 · 左边点标题换篇")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.gold)
                } else {
                    // 漫画格：左右翻格；正文页：上下只滚文章（换篇用左边目录）
                    let textPage = urls.count
                    let pageCount = urls.count + 1
                    let onComicPage = comicPage < textPage
                    comicAndTextPager(
                        story: story,
                        urls: urls,
                        pageCount: pageCount
                    )

                    Text(
                        onComicPage
                            ? "左右滑翻格 · \(comicPage + 1)/\(urls.count)"
                            : "正文 · 上下拉看全文 · 左右滑回漫画"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.gold)
                }
            } else {
                VStack(spacing: 12) {
                    GuangguangTalking(talking: false, size: 140)
                    Text("选左边一篇，这里看预览")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.pine.opacity(0.75))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Palette.foam.opacity(0.94))
                .shadow(color: Palette.pine.opacity(0.08), radius: 10, y: 3)
        )
    }

    /// 漫画 + 正文翻页；换篇请点左边目录，这里不做上下滑换篇。
    @ViewBuilder
    private func comicAndTextPager(
        story: BedtimeStory,
        urls: [URL],
        pageCount: Int
    ) -> some View {
        LoopingPageTabView(pageCount: pageCount, selection: $comicPage) { index in
            if urls.indices.contains(index) {
                Group {
                    if let uiImage = ComicImageCache.image(at: urls[index]) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(8)
                    }
                }
            } else {
                ScrollView {
                    Text(story.text)
                        .font(.title3)
                        .foregroundStyle(Palette.dusk)
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
        }
        .id(story.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ensurePreview() {
        if let current = previewStory, stories.contains(where: { $0.id == current.id }) {
            return
        }
        if let playingId = audio.playingId,
           let match = stories.first(where: { $0.id == playingId })
        {
            previewStory = match
            return
        }
        previewStory = stories.first(where: { BedtimeComics.hasComics(for: $0.id) }) ?? stories.first
    }
}

private struct CatalogLeafBackground: View {
    var body: some View {
        ZStack {
            Palette.mist
            // iPhone 用纯色底更省；大图全屏铺满容易拖慢滑动
            if HavenLayout.isPad, UIImage(named: "CatalogLeafBg") != nil {
                Image("CatalogLeafBg")
                    .resizable()
                    .scaledToFill()
                    .opacity(0.92)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

/// 书架卡片按下时轻轻缩小，反馈更清楚
private struct ShelfCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 循环翻页：滑过最后一页回到第一页，滑过第一页到最后一页。
private struct LoopingPageTabView<Page: View>: View {
    let pageCount: Int
    @Binding var selection: Int
    @ViewBuilder var page: (Int) -> Page

    @State private var internalPage = 1

    var body: some View {
        Group {
            if pageCount <= 0 {
                EmptyView()
            } else if pageCount == 1 {
                safePage(0)
            } else {
                TabView(selection: $internalPage) {
                    safePage(pageCount - 1)
                        .tag(0)
                    ForEach(0 ..< pageCount, id: \.self) { index in
                        safePage(index)
                            .tag(index + 1)
                    }
                    safePage(0)
                        .tag(pageCount + 1)
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .onAppear { syncInternal(from: selection) }
                .onChange(of: selection) { _, newValue in
                    let clamped = min(max(newValue, 0), pageCount - 1)
                    let target = clamped + 1
                    if internalPage != target,
                       internalPage > 0,
                       internalPage < pageCount + 1
                    {
                        internalPage = target
                    }
                }
                .onChange(of: internalPage) { _, newValue in
                    if newValue == 0 {
                        jumpWithoutAnimation(to: pageCount)
                        selection = pageCount - 1
                    } else if newValue == pageCount + 1 {
                        jumpWithoutAnimation(to: 1)
                        selection = 0
                    } else if newValue >= 1, newValue <= pageCount {
                        selection = newValue - 1
                    }
                }
                .onChange(of: pageCount) { _, _ in
                    selection = min(max(selection, 0), max(0, pageCount - 1))
                    syncInternal(from: selection)
                }
            }
        }
    }

    @ViewBuilder
    private func safePage(_ index: Int) -> some View {
        if pageCount > 0, (0 ..< pageCount).contains(index) {
            page(index)
        } else {
            Color.clear
        }
    }

    private func syncInternal(from logical: Int) {
        let clamped = min(max(logical, 0), max(0, pageCount - 1))
        internalPage = pageCount <= 1 ? 1 : clamped + 1
    }

    private func jumpWithoutAnimation(to value: Int) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            internalPage = value
        }
    }
}

private func catalogRow(
    index: Int,
    story: BedtimeStory,
    isPlaying: Bool,
    isCurrent: Bool,
    isPreviewSelected: Bool,
    hasAudio: Bool,
    isLocked: Bool = false,
    isFreeBadge: Bool = false,
    onSelect: @escaping () -> Void,
    onPlay: @escaping () -> Void
) -> some View {
    HStack(alignment: .center, spacing: 12) {
        // 序号与播放合为一颗圆钮：未播显示编号，正在播显示暂停
        Button(action: onPlay) {
            ZStack {
                Circle()
                    .fill(
                        isPlaying
                            ? Palette.moss
                            : (isLocked
                                ? Palette.mist
                                : (hasAudio ? Palette.gold.opacity(0.85) : Palette.mist))
                    )
                if isPlaying {
                    Image(systemName: "pause.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.foam)
                } else if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.pine.opacity(0.55))
                } else if isCurrent, hasAudio {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.pine)
                } else {
                    Text(String(format: "%02d", index))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(hasAudio ? Palette.pine : Palette.pine.opacity(0.4))
                }
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!hasAudio && !isLocked)
        .accessibilityLabel(isPlaying ? "暂停" : "听故事")

        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(story.title)
                    .font(.headline)
                    .foregroundStyle(Palette.dusk)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isFreeBadge {
                    Text("试听")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.moss)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.moss.opacity(0.15)))
                } else if isLocked {
                    Text("会员")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.pine.opacity(0.65))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.mist))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isPreviewSelected ? Palette.foam : Palette.foam.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isPreviewSelected ? Palette.moss.opacity(0.55) : Color.clear,
                        lineWidth: 2
                    )
            )
    )
}

struct BedtimeStoryPage: View {
    var story: BedtimeStory
    @Environment(MembershipStore.self) private var membership
    @State private var audio = BedtimeAudioPlayer.shared
    @State private var comicPage = 0

    private var isThisPlaying: Bool {
        audio.playingId == story.id && audio.isPlaying
    }

    private var hasAudio: Bool {
        audio.hasAudio(for: story.id)
    }

    private var comicURLs: [URL] {
        BedtimeComics.panelURLs(for: story.id)
    }

    static func playQueue(for story: BedtimeStory) -> [BedtimeStory] {
        BedtimeCatalogStore.shared.playQueue(for: story)
    }

    var body: some View {
        @Bindable var membership = membership
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if comicURLs.isEmpty {
                    GuangguangTalking(
                        talking: isThisPlaying,
                        size: HavenLayout.isPad ? 180 : 132
                    )
                    .frame(maxWidth: .infinity)
                }

                Text("\(story.shelfTitle) · \(story.ageTitle)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.gold)
                Text(story.title)
                    .font(HavenLayout.isPad ? .largeTitle.weight(.bold) : .title.weight(.bold))
                    .foregroundStyle(Palette.pine)

                if !comicURLs.isEmpty {
                    comicPager
                }

                Button {
                    if isThisPlaying {
                        audio.togglePauseResume()
                        return
                    }
                    guard membership.requestPlay(story) else { return }
                    let queue = Self.playQueue(for: story)
                    audio.toggle(story, queue: queue)
                } label: {
                    Label(
                        isThisPlaying ? "暂停" : (membership.showsLock(for: story) ? "会员可听" : "听故事"),
                        systemImage: isThisPlaying ? "pause.fill" : (membership.showsLock(for: story) ? "lock.fill" : "play.fill")
                    )
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.moss)
                .disabled(!hasAudio && !membership.showsLock(for: story))
                .accessibilityLabel(isThisPlaying ? "暂停" : "听故事")

                if !hasAudio {
                    Text("这篇还没录好声音，可以先看文字。")
                        .font(.footnote)
                        .foregroundStyle(Palette.dusk.opacity(0.75))
                }

                Text(story.text)
                    .font(HavenLayout.isPad ? .title3 : .body)
                    .foregroundStyle(Palette.dusk)
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(HavenLayout.isPad ? 36 : 22)
            .frame(maxWidth: HavenLayout.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.foam.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BedtimeNowPlayingButton()
            }
        }
        .sheet(isPresented: $membership.showPaywall) {
            MembershipPaywallSheet()
                .environment(membership)
        }
    }

    private var comicPager: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("漫画 · 循环滑翻格")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.pine.opacity(0.65))

            LoopingPageTabView(pageCount: comicURLs.count, selection: $comicPage) { index in
                Group {
                    if index < comicURLs.count,
                       let uiImage = ComicImageCache.image(at: comicURLs[index])
                    {
                        Image(uiImage: uiImage)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .frame(height: HavenLayout.isPad ? 420 : 280)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.mist)
            )

            Text("第 \(comicPage + 1) / \(comicURLs.count) 格 · 滑完回到第 1 格")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.gold)
        }
    }
}

/// 导航栏右侧播放键。传入 currentStory 时只播/暂停这一篇；否则沿用全局继续播放。
private struct BedtimeNowPlayingButton: View {
    var currentStory: BedtimeStory? = nil
    var queue: [BedtimeStory] = []

    @Environment(MembershipStore.self) private var membership
    @State private var audio = BedtimeAudioPlayer.shared

    private var controlsCurrent: Bool { currentStory != nil }

    private var isCurrentPlaying: Bool {
        guard let id = currentStory?.id else { return audio.isPlaying }
        return audio.playingId == id && audio.isPlaying
    }

    private var canTap: Bool {
        if let story = currentStory {
            return audio.hasAudio(for: story.id) || membership.showsLock(for: story)
        }
        return audio.canControlPlayback
    }

    var body: some View {
        Button {
            if let story = currentStory {
                // 只针对当前预览这篇：同篇则暂停/继续，否则改播这篇
                if audio.playingId == story.id {
                    audio.togglePauseResume()
                } else if audio.hasAudio(for: story.id) {
                    guard membership.requestPlay(story) else { return }
                    audio.play(story, queue: queue.isEmpty ? nil : queue)
                } else if membership.showsLock(for: story) {
                    _ = membership.requestPlay(story)
                }
            } else {
                audio.togglePauseResume()
            }
        } label: {
            Image(systemName: isCurrentPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    canTap ? Palette.moss : Palette.pine.opacity(0.28),
                    canTap ? Palette.moss.opacity(0.18) : Palette.mist
                )
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canTap)
        .accessibilityLabel(
            isCurrentPlaying
                ? "暂停"
                : (controlsCurrent ? "播放当前这篇" : "继续播放")
        )
    }
}

/// 播放台整卡保留光光；有漫画时播放会自动翻到漫画页，循环滑动。
private struct GuangguangBanner: View {
    var fillsAvailableHeight: Bool = false

    @State private var audio = BedtimeAudioPlayer.shared
    /// 0 = 光光播放台；1… = 漫画第几格（真实页码，手滑与自动翻都写这里）
    @State private var bannerPage = 0
    /// 手滑过后暂不强行跟进度；换篇后再自动跟
    @State private var userPickedPage = false

    private var robotSize: CGFloat { HavenLayout.isPad ? 180 : 120 }
    private var cardHeight: CGFloat { HavenLayout.isPad ? 420 : 280 }

    private var comicURLs: [URL] {
        guard let id = audio.nowPlayingStory?.id else { return [] }
        return BedtimeComics.panelURLs(for: id)
    }

    private var hasComics: Bool { !comicURLs.isEmpty }

    /// 播放台 + 漫画格（循环）
    private var loopPageCount: Int { 1 + comicURLs.count }

    private var pageSelection: Binding<Int> {
        Binding(
            get: { bannerPage },
            set: { newValue in
                guard newValue != bannerPage else { return }
                bannerPage = newValue
                userPickedPage = true
            }
        )
    }

    var body: some View {
        Group {
            if hasComics {
                LoopingPageTabView(pageCount: loopPageCount, selection: pageSelection) { index in
                    if index == 0 {
                        playerCard
                    } else if comicURLs.indices.contains(index - 1) {
                        fullComicPage(url: comicURLs[index - 1], index: index - 1)
                    } else {
                        playerCard
                    }
                }
                .id(audio.nowPlayingStory?.id ?? "banner")
                .frame(maxWidth: .infinity)
                .frame(height: fillsAvailableHeight ? nil : cardHeight)
                .frame(maxHeight: fillsAvailableHeight ? .infinity : nil)
                .background {
                    // 仅播放中才轮询翻格；停播时不跑定时，省电、少卡顿
                    if audio.isPlaying {
                        TimelineView(.periodic(from: .now, by: 1.0)) { context in
                            Color.clear
                                .onChange(of: context.date) { _, _ in
                                    syncComicPageIfNeeded()
                                }
                        }
                    }
                }
            } else {
                playerCard
                    .frame(height: fillsAvailableHeight ? nil : (HavenLayout.isPad ? 280 : 220))
                    .frame(maxHeight: fillsAvailableHeight ? .infinity : nil)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Palette.pine.opacity(0.08), radius: 10, y: 3)
        .onChange(of: audio.nowPlayingStory?.id) { _, _ in
            userPickedPage = false
            bannerPage = (audio.isPlaying && hasComics) ? 1 : 0
        }
        .onChange(of: comicURLs.count) { _, count in
            if bannerPage > count {
                bannerPage = hasComics ? 1 : 0
            }
        }
        .onChange(of: audio.isPlaying) { _, playing in
            guard hasComics, playing else { return }
            // 开始播：自动到漫画；若孩子已滑回播放台，尊重选择不抢走
            if !userPickedPage, bannerPage == 0 {
                bannerPage = 1
            }
        }
    }

    /// 播放中且未手滑时，按正文进度停在漫画 1…n（标题段 bodyProgress=0，先停在第 1 格）
    private func syncComicPageIfNeeded() {
        guard hasComics, !userPickedPage, audio.isPlaying else { return }
        let count = comicURLs.count
        guard count > 0 else { return }
        let progress = audio.bodyProgress
        let comicIndex = progress > 0.02
            ? min(count - 1, max(0, Int(progress * Double(count))))
            : 0
        let target = 1 + comicIndex
        if bannerPage != target {
            bannerPage = target
        }
    }

    /// 光光 + 迷你播放台（右边始终是光光）
    private var playerCard: some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    hasComics
                        ? "我是光光，你的机器人朋友。\n播放时到漫画：左右翻格即可。"
                        : "我是光光，你的机器人朋友。\n想听故事时，叫我就好。"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.pine.opacity(0.85))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

                MiniPlayerDock()

                nowPlayingCaption
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GuangguangTalking(
                talking: audio.isPlaying,
                size: robotSize
            )
            .accessibilityHidden(true)
            .padding(.trailing, 2)
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bannerBackground)
    }

    private func fullComicPage(url: URL, index: Int) -> some View {
        ZStack(alignment: .bottom) {
            bannerBackground

            if let uiImage = ComicImageCache.image(at: url) {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .padding(.bottom, 22)
            }

            Text("漫画 \(index + 1)/\(comicURLs.count) · 左右翻格")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.pine)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Palette.foam.opacity(0.92)))
                .padding(.bottom, 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel("本集漫画第\(index + 1)格，共\(comicURLs.count)格，左右翻格")
    }

    private var bannerBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Palette.sage.opacity(0.45), Palette.foam],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    @ViewBuilder
    private var nowPlayingCaption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(statusText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.gold)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(titleText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.pine)
                    .lineLimit(1)
                if let extra = queueHint {
                    Text(extra)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.pine.opacity(0.55))
                }
            }
        }
    }

    private var statusText: String {
        if audio.isPlaying { return "正在播放" }
        if audio.hasNowPlaying { return "已暂停" }
        if audio.nowPlayingStory != nil { return "上次听到" }
        return "还没开始"
    }

    private var titleText: String {
        audio.nowPlayingStory?.title ?? "点一篇，这里会显示名字"
    }

    private var queueHint: String? {
        guard let story = audio.nowPlayingStory else { return nil }
        let list = BedtimeStoryPage.playQueue(for: story)
            .filter { audio.hasAudio(for: $0.id) }
        guard let idx = list.firstIndex(where: { $0.id == story.id }) else { return nil }
        return "\(idx + 1)/\(list.count)"
    }
}

/// 左下迷你台：上一篇 / 播放 / 下一篇 / 语速。
private struct MiniPlayerDock: View {
    @State private var audio = BedtimeAudioPlayer.shared

    var body: some View {
        HStack(spacing: 10) {
            dockIconButton(
                systemName: "backward.end.fill",
                enabled: audio.canPlayPrevious,
                label: "上一篇"
            ) {
                audio.playPrevious()
            }

            dockIconButton(
                systemName: audio.isPlaying ? "pause.fill" : "play.fill",
                enabled: audio.canControlPlayback || audio.nowPlayingStory != nil,
                label: audio.isPlaying ? "暂停" : "播放",
                prominent: true
            ) {
                audio.togglePauseResume()
            }

            dockIconButton(
                systemName: "forward.end.fill",
                enabled: audio.canPlayNext,
                label: "下一篇"
            ) {
                audio.playNext()
            }

            Button {
                audio.cyclePlaybackRate()
            } label: {
                Text(audio.rateLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.pine)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Palette.sage.opacity(0.55))
                    )
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityLabel("语速\(audio.rateLabel)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.foam.opacity(0.95))
        )
    }

    private func dockIconButton(
        systemName: String,
        enabled: Bool,
        label: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(prominent ? .body.weight(.bold) : .caption.weight(.bold))
                .foregroundStyle(enabled ? Palette.pine : Palette.pine.opacity(0.28))
                .frame(width: prominent ? 28 : 22, height: prominent ? 28 : 22)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// 故事页里的光光。身子不晃。播放录音时换嘴巴和手。脚下淡影与图标一致。
private struct GuangguangTalking: View {
    var talking: Bool
    var size: CGFloat

    /// iPhone 嘴型切换放慢一点，少解码大图
    private var mouthInterval: Double { HavenLayout.isPad ? 0.22 : 0.34 }

    var body: some View {
        TimelineView(.animation(minimumInterval: mouthInterval, paused: !talking)) { context in
            Image(Self.frameName(talking: talking, date: context.date, interval: mouthInterval))
                .resizable()
                .interpolation(HavenLayout.isPad ? .high : .medium)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel("光光")
        }
    }

    private static func frameName(talking: Bool, date: Date, interval: Double) -> String {
        guard talking else { return "Guangguang" }
        let open = Int(date.timeIntervalSinceReferenceDate / interval) % 2 == 0
        return open ? "GuangguangTalkA" : "GuangguangTalkB"
    }
}

#Preview {
    TipsView()
        .environment(BedtimeCatalogStore.shared)
}
