import SwiftUI

/// 故事书架。不要在这里引用 RestSession、RestStoryPlayer 或发通知。
struct TipsView: View {
    @State private var age: BedtimeAge = Self.savedAge()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("年龄", selection: $age) {
                    ForEach(BedtimeAge.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, HavenLayout.isPad ? 28 : 16)
                .padding(.top, 10)
                .padding(.bottom, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(spacing: 10) {
                            Image("Guangguang")
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: HavenLayout.isPad ? 280 : 220,
                                    height: HavenLayout.isPad ? 280 : 220
                                )
                                .frame(maxWidth: .infinity)
                            Text("光光")
                                .font(HavenLayout.isPad ? .title.weight(.bold) : .title2.weight(.bold))
                                .foregroundStyle(Palette.dusk)
                            Text("写故事的小机器人。胸口一盏暖灯，每晚只问一个真问题。")
                                .font(.subheadline)
                                .foregroundStyle(Palette.pine.opacity(0.75))
                                .multilineTextAlignment(.center)
                            Text(age.hint)
                                .font(.footnote)
                                .foregroundStyle(Palette.pine.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                        Text("书架")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.moss)
                            .tracking(1)

                        NavigationLink {
                            WhyBookPage(age: age)
                        } label: {
                            bookCard(
                                badge: "短篇",
                                title: "小为什么",
                                meta: "\(BedtimeLibrary.stories(for: age).count) 则 · 一则一个问题",
                                line: "打开就能看完。适合睡前随手翻。"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            SerialBookPage(series: SerialLibrary.series(for: age))
                        } label: {
                            let series = SerialLibrary.series(for: age)
                            bookCard(
                                badge: "连载",
                                title: series.title,
                                meta: "\(series.episodes.count) 集 · 已写完 \(series.readyCount) 集",
                                line: series.pitch
                            )
                        }
                        .buttonStyle(.plain)

                        Text("先选年龄，再选一本。书多了也按本收，不把篇目摊在一页上。")
                            .font(.caption)
                            .foregroundStyle(Palette.pine.opacity(0.55))
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, HavenLayout.isPad ? 28 : 16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: HavenLayout.pageMaxWidth)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Palette.mist.ignoresSafeArea())
            .navigationTitle("故事")
            .onChange(of: age) { _, newAge in
                UserDefaults.standard.set(newAge.rawValue, forKey: Self.ageKey)
            }
        }
    }

    private func bookCard(badge: String, title: String, meta: String, line: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.gold.opacity(0.9))
                .frame(width: 52, height: 72)
                .overlay {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.pine)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.dusk)
                Text(meta)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.gold)
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(Palette.pine.opacity(0.75))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.moss.opacity(0.7))
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.foam)
        )
    }

    private static let ageKey = "bedtime.age"

    private static func savedAge() -> BedtimeAge {
        if let raw = UserDefaults.standard.string(forKey: ageKey) {
            if let age = BedtimeAge(rawValue: raw) { return age }
            if raw == "9-12岁" { return .older }
        }
        return .little
    }
}

struct WhyBookPage: View {
    var age: BedtimeAge
    @State private var selected: BedtimeStory?

    private var stories: [BedtimeStory] { BedtimeLibrary.stories(for: age) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("共 \(stories.count) 则 · \(age.rawValue)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.gold)

                ForEach(Array(stories.enumerated()), id: \.element.id) { index, story in
                    Button {
                        selected = story
                    } label: {
                        catalogRow(
                            index: index + 1,
                            title: story.title,
                            preview: story.text,
                            ready: true
                        )
                    }
                    .buttonStyle(.plain)
                }

                Text("这些小为什么是新写的常识，不是哪一本书的摘录。")
                    .font(.caption)
                    .foregroundStyle(Palette.pine.opacity(0.55))
                    .padding(.top, 8)
            }
            .padding(HavenLayout.isPad ? 28 : 16)
            .frame(maxWidth: HavenLayout.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.mist.ignoresSafeArea())
        .navigationTitle("小为什么")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selected) { story in
            BedtimeStoryPage(story: story)
        }
    }
}

struct SerialBookPage: View {
    var series: SerialSeries
    @State private var selected: SerialEpisode?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(series.pitch)
                    .font(.subheadline)
                    .foregroundStyle(Palette.pine.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                Text("已写完 \(series.readyCount) / \(series.episodes.count) 集")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.gold)

                ForEach(series.episodes) { episode in
                    Button {
                        selected = episode
                    } label: {
                        catalogRow(
                            index: episode.number,
                            title: episode.title,
                            preview: episode.hook,
                            ready: episode.text != nil
                        )
                    }
                    .buttonStyle(.plain)
                }

                Text("每集只讲透一个知识点。没写完的先留下一问，免得一次翻完。")
                    .font(.caption)
                    .foregroundStyle(Palette.pine.opacity(0.55))
                    .padding(.top, 8)
            }
            .padding(HavenLayout.isPad ? 28 : 16)
            .frame(maxWidth: HavenLayout.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.mist.ignoresSafeArea())
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selected) { episode in
            SerialEpisodePage(seriesTitle: series.title, episode: episode)
        }
    }
}

private func catalogRow(index: Int, title: String, preview: String, ready: Bool) -> some View {
    HStack(alignment: .top, spacing: 12) {
        Text(String(format: "%02d", index))
            .font(.caption.weight(.bold))
            .foregroundStyle(ready ? Palette.pine : Palette.pine.opacity(0.4))
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(ready ? Palette.gold.opacity(0.85) : Palette.mist)
            )

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Palette.dusk)
                if !ready {
                    Text("预告")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.moss)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.mist))
                }
            }
            Text(preview)
                .font(.subheadline)
                .foregroundStyle(Palette.pine.opacity(0.75))
                .lineLimit(2)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.moss.opacity(0.7))
            .padding(.top, 6)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Palette.foam)
    )
}

struct BedtimeStoryPage: View {
    var story: BedtimeStory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("小为什么 · \(story.age.rawValue)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.gold)
                Text(story.title)
                    .font(HavenLayout.isPad ? .largeTitle.weight(.bold) : .title.weight(.bold))
                    .foregroundStyle(Palette.pine)
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
    }
}

struct SerialEpisodePage: View {
    var seriesTitle: String
    var episode: SerialEpisode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(seriesTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.gold)
                Text("第\(episode.number)集")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.moss)
                Text(episode.title)
                    .font(HavenLayout.isPad ? .largeTitle.weight(.bold) : .title.weight(.bold))
                    .foregroundStyle(Palette.pine)
                if let text = episode.text {
                    Text(text)
                        .font(HavenLayout.isPad ? .title3 : .body)
                        .foregroundStyle(Palette.dusk)
                        .lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(episode.hook)
                        .font(HavenLayout.isPad ? .title3 : .body)
                        .foregroundStyle(Palette.dusk)
                        .lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("正文还在这一本后面。一次看完，就没有下一问了。")
                        .font(.subheadline)
                        .foregroundStyle(Palette.pine.opacity(0.7))
                        .padding(.top, 8)
                }
            }
            .padding(HavenLayout.isPad ? 36 : 22)
            .frame(maxWidth: HavenLayout.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.foam.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    TipsView()
}
