import Foundation

/// 知识连载。只给故事页看，不要接到休息计时、朗读或通知。
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
        switch age {
        case .little: littleQuestion
        case .middle: natureNotebook
        case .older: extraPage
        }
    }

    /// 3-5 岁：每集学会一个为什么，下一集带着新问题出门。
    static let littleQuestion = SerialSeries(
        id: "little-question",
        age: .little,
        title: "光光出门",
        pitch: "光光是写这些故事的小机器人。圆脑袋，屏幕会笑，头上有一颗小星星。每晚只问一件真事。问完就回家。",
        episodes: [
            .init(
                id: "q-01",
                number: 1,
                title: "天为什么是蓝的",
                hook: "光光第一次抬头。答案有了，可傍晚的天又换了颜色。",
                text: """
                窗台上住着光光。它是一只小小的机器人，圆脑袋，脸上是一块会笑的屏幕，头顶一颗暖黄的小星星。它最喜欢跟在小朋友后头，看见什么都要问一声。
                今天它把灯调亮一点，看见整片天都是蓝的。它问太阳：“你是黄的，天为什么不黄？”太阳说：“我的光里有很多颜色。空气里的小颗粒最爱把蓝色推来推去，蓝色就铺满了上面。”
                光光把这句话记进胸口那盏小灯：不是天涂了颜料，是蓝光最会散开。
                傍晚，天忽然有点红。光光屏幕上的眼睛睁圆了：“蓝的不是散开了吗？红又是谁？”
                太阳已经落到楼后面，只留下一句：“光走过更长的空气，会换一件衣服。明天再问。”
                第一集到这里。蓝的学会了。红的，要等下一回出门。
                """
            ),
            .init(id: "q-02", number: 2, title: "晚霞为什么是红的", hook: "光走远了，蓝的先散掉，红的留下来。可天全黑以后，红又去哪了？", text: nil),
            .init(id: "q-03", number: 3, title: "月亮为什么好像跟着走", hook: "树会溜走，月亮几乎不动。因为它太远了。那星星为什么一眨一眨？", text: nil),
            .init(id: "q-04", number: 4, title: "星星为什么会眨眼", hook: "星星自己是稳的，空气把光弯了一下。那流星是星星在跑吗？", text: nil),
            .init(id: "q-05", number: 5, title: "流星不是星星在搬家", hook: "那是小石头擦亮空气。光光头顶的星星亮了一下：那雨是天在哭吗？", text: nil),
            .init(id: "q-06", number: 6, title: "雨点为什么会唱歌", hook: "小水滴敲叶子，空气就响。雨停了，天上为什么又弯出一条彩带子？", text: nil),
            .init(id: "q-07", number: 7, title: "彩虹是怎么挂上去的", hook: "小水滴把白光拆开。彩虹走了以后，衣服上的水珠还会闪，那是同一件事吗？", text: nil),
            .init(id: "q-08", number: 8, title: "影子为什么跟着我", hook: "身体挡住光，就有影子。关灯以后影子回家了。那镜子里的人是影子吗？", text: nil),
            .init(id: "q-09", number: 9, title: "镜子里为什么有另一个我", hook: "光撞上玻璃再折回来。镜子里的人却左右反了。为什么书在镜子里会反着写？", text: nil),
            .init(id: "q-10", number: 10, title: "为什么会打哈欠", hook: "身体在说该歇了。看见别人打哈欠，自己也会。那睡觉时眼睛为什么要关上？", text: nil),
            .init(id: "q-11", number: 11, title: "人为什么一定要睡觉", hook: "脑子要整理白天，眼睛的肌肉要松开。不睡，明天会慢。可小猫夜里为什么还看得见？", text: nil),
            .init(id: "q-12", number: 12, title: "小猫夜里为什么看得清", hook: "眼睛后面像有小镜子。你不是小猫，夜里可以暗一点。光光把十二个答案收进小灯，明天换一条路。", text: nil)
        ]
    )

    /// 6-8 岁：每集一个能讲给同学听的真知识，笔记还夹着下一页。
    static let natureNotebook = SerialSeries(
        id: "nature-note",
        age: .middle,
        title: "带锁的博物笔记",
        pitch: "一本只能一页一页打开的笔记。每页写清一件真事：海水为什么咸、先看见闪电后听见雷。听完能去学校讲，也像买了一本会更新的课外书。",
        episodes: [
            .init(
                id: "n-01",
                number: 1,
                title: "海水为什么是咸的",
                hook: "河是淡的，海是咸的。盐从哪来，下一页还画着冰。",
                text: """
                笔记第一页只有一句话：“把全世界的河加起来，也变不成一勺海水的咸。”下面有一把小锁。
                锁打开，字才出现。雨落到石头上，会溶解一点点盐，送进河里，再送进海里。太阳把水晒上天，盐却留在海里。很多很多年以后，海就咸了。
                你喝的淡水，是云把盐留下以后又送回来的。所以河一直淡，海一直咸。不是海自己放了酱油。
                页脚画了一朵冰花，旁边写着：“冬天的玻璃也会开花。盐和水，到了冷的地方，还会变把戏。”
                小锁咔哒一声。第二页只露出边：玻璃、哈气、白色的纹。
                第一集到这里。咸的学会了。花一样的冰，要等下一页。
                """
            ),
            .init(id: "n-02", number: 2, title: "冬天玻璃上为什么有花", hook: "水汽碰上冷玻璃，冰晶顺着纹路生长。下一页问：这些水，会不会变成雨再回来？", text: nil),
            .init(id: "n-03", number: 3, title: "水会在天上地下绕圈", hook: "蒸发、成云、下雨、再流走。下一页的蜜蜂也在绕圈，不过它绕的是花。", text: nil),
            .init(id: "n-04", number: 4, title: "蜜蜂为什么要采花", hook: "花蜜变成能存放的蜜，花粉被带到另一朵花上。下一页：没有花，树叶自己还能做饭吗？", text: nil),
            .init(id: "n-05", number: 5, title: "叶子用阳光做饭", hook: "叶绿素留下阳光里的能量。秋天绿衣服收回去，黄和红才露出来。下一页打雷。", text: nil),
            .init(id: "n-06", number: 6, title: "为什么先看见闪电后听见雷", hook: "光和雷是同一件事，光快、声慢。下一页：那声音在水里和空气里，谁更快？", text: nil),
            .init(id: "n-07", number: 7, title: "水里的声音跑得更快", hook: "水比空气密，振动传得更利索。鲸鱼能隔得很远“说话”。下一页回到人自己。", text: nil),
            .init(id: "n-08", number: 8, title: "人为什么一定要睡觉", hook: "脑子整理记忆，眼睛的肌肉松开。下一页：睡着了为什么还会做梦？", text: nil),
            .init(id: "n-09", number: 9, title: "做梦时脑子并没有下班", hook: "有一段睡眠几乎和醒着一样忙，身体却被轻轻刹车。下一页：地球自己会不会做梦一样转晕？", text: nil),
            .init(id: "n-10", number: 10, title: "地球为什么不会掉下去", hook: "太阳拉着，地球又跑得够快。下一页：那我们头朝下的人，为什么掉不出去？", text: nil),
            .init(id: "n-11", number: 11, title: "地球另一面的人不会掉到天上", hook: "重力指向地心，哪里都是“下”。最后一页锁着一张旧地图。", text: nil),
            .init(id: "n-12", number: 12, title: "地图上的北，不是指南针的北", hook: "地磁北极和地理北极差一截。笔记合上，锁还在。第二本从磁偏角开始。", text: nil)
        ]
    )

    /// 9-16 岁：课本边上一问，每集一个能写进笔记的真原理。
    static let extraPage = SerialSeries(
        id: "extra-page",
        age: .older,
        title: "课本没写完的一页",
        pitch: "给小学高年级到初中。每集把一个真原理讲清楚：散射、潮汐、生物钟、近视怎么形成。像加厚的课外讲义，一次只讲透一题，方便家长当学习内容付钱。",
        episodes: [
            .init(
                id: "e-01",
                number: 1,
                title: "白天为什么蓝、夜里为什么黑",
                hook: "散射把蓝光铺满天空。太阳一下地平线，对比还给星星。下一题：月亮自己会发光吗？",
                text: """
                课本写：“晴天是蓝色的。”下面没有为什么。这一页把它写完。
                阳光里有许多颜色。空气分子特别会把短波的蓝光向四面八方散射，于是整片天都浸在蓝光里。中午太阳高，路短，蓝得干净；傍晚路长，蓝光沿途散掉更多，红橙才剩下来，那是晚霞。
                太阳落到地平线以下，散射的光不够用了，天就暗。星星其实一直在，只是白天被散射光比下去了。你看见的“黑”，是对比，不是世界被关掉。
                页边还有一行铅笔：月亮很亮，却常常有人以为它自己会烧。它不会。下一页只写了两个字：“反射”。
                第一集到这里。蓝和黑弄清楚了。月亮的圆缺，是下一题。
                """
            ),
            .init(id: "e-02", number: 2, title: "月亮为什么有时圆有时缺", hook: "它只反射太阳光，缺的一块还在。下一题：潮汐和月亮有什么关系？", text: nil),
            .init(id: "e-03", number: 3, title: "海为什么会涨会退", hook: "月亮拉水，太阳也拉。排成一线时潮差最大。下一题：拉得动海，为什么拉不动你手里的杯子？", text: nil),
            .init(id: "e-04", number: 4, title: "引力处处都在，只是你习惯了", hook: "杯子太小，潮汐差看不出来。下一题：指南针指的北，是地理北吗？", text: nil),
            .init(id: "e-05", number: 5, title: "指南针为什么总指向北方", hook: "地磁场，磁北极和地理北极有偏差。下一题：钢梁旁边指针为什么会打架？", text: nil),
            .init(id: "e-06", number: 6, title: "磁铁为什么只喜欢铁", hook: "铁里有能转向的磁畴。下一题：光和声音谁快，快多少？", text: nil),
            .init(id: "e-07", number: 7, title: "光和声音谁跑得快", hook: "大约一百万倍。所以先看见闪电。下一题：空气明明在，为什么看不见？", text: nil),
            .init(id: "e-08", number: 8, title: "空气明明在，为什么看不见", hook: "分子几乎不吸收可见光。下一题：那雾为什么看得见？", text: nil),
            .init(id: "e-09", number: 9, title: "雾、灰尘，怎样把“空”变成能看见的", hook: "小水滴把光挡住、反射出来。下一题回到人：为什么越大越想晚睡？", text: nil),
            .init(id: "e-10", number: 10, title: "为什么越大越想晚睡", hook: "青春期生物钟后移。下一题：做梦是不是在预言？", text: nil),
            .init(id: "e-11", number: 11, title: "睡觉时脑子为什么还会做梦", hook: "快速眼动睡眠，身体被刹车。梦多半是整理，不是预言。最后一题关于眼睛。", text: nil),
            .init(id: "e-12", number: 12, title: "眼睛为什么会越看越近", hook: "长时间看近，眼球可能变长。不是一天发生的。第一本到此。下一本从“看远一分钟到底发生了什么”开始。", text: nil)
        ]
    )
}
