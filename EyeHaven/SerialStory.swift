import Foundation

/// 旧「知识连载」已换成书架上的《光光讲知识》《光光睡前小故事》。
/// 保留空壳，避免旧预览或引用编译失败。不要接到休息计时。
struct SerialEpisode: Identifiable, Hashable {
    var id: String
    var number: Int
    var title: String
    var hook: String
    var text: String?
}

struct SerialSeries: Identifiable, Hashable {
    var id: String
    var age: BedtimeAge
    var title: String
    var pitch: String
    var episodes: [SerialEpisode]

    var readyCount: Int { episodes.filter { $0.text != nil }.count }
}

enum SerialLibrary {
    static func series(for age: BedtimeAge) -> SerialSeries {
        SerialSeries(
            id: "retired-\(age.rawValue)",
            age: age,
            title: "已下架",
            pitch: "请到语音书架打开《光光讲知识》或《光光睡前小故事》。",
            episodes: []
        )
    }
}
