import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit

/// 睡前故事文案与故事页播放。不要接到休息计时、锁屏或通知。

/// 故事页专用：播打包好的火山配音 mp3。与休息页系统朗读分开。
@MainActor
@Observable
final class BedtimeAudioPlayer {
    static let shared = BedtimeAudioPlayer()

    /// 可选语速（相对原速）。睡前默认稍慢。
    static let rateOptions: [(label: String, rate: Float)] = [
        ("慢", 0.75),
        ("稍慢", 0.85),
        ("正常", 1.0),
        ("稍快", 1.15),
    ]

    private static let rateKey = "bedtime.audio.playbackRate"
    private static let lastIdKey = "bedtime.audio.lastStoryId"
    /// 每个年龄×书架各自记住最后一篇：key = "ageId|shelfId"
    private static let lastByShelfKey = "bedtime.audio.lastByShelf"

    private(set) var playingId: String?
    private(set) var isPlaying = false
    /// 上次听过的篇目，关掉 App 后还能点播放继续听。
    private(set) var lastStoryId: String?
    /// 各类别独立进度（供书架「继续播放」）
    private(set) var lastStoryIdByShelf: [String: String] = [:]

    /// 播放倍速，写入本地，下次打开还在。
    var playbackRate: Float {
        didSet {
            guard abs(playbackRate - oldValue) > 0.001 else { return }
            UserDefaults.standard.set(playbackRate, forKey: Self.rateKey)
            if isPlaying, !isAnnouncingTitle {
                player?.rate = playbackRate
                refreshNowPlayingElapsed()
            }
        }
    }

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var didSetupRemote = false
    /// 当前书架队列；播完自动找下一篇有声音的
    private var queue: [BedtimeStory] = []
    /// 开篇先播火山「请听+标题」，再播正文
    private let titleSynth = AVSpeechSynthesizer()
    private let titleBridge = TitleSpeechBridge()
    private var isAnnouncingTitle = false
    private var waitingToStartBody = false
    private var usingTitleMp3 = false
    private var pendingBodyURL: URL?
    private var gapTask: Task<Void, Never>?
    /// 被电话等打断前正在播；结束后要自动接着播（熄屏误报打断也靠这个恢复）
    private var resumeAfterInterruption = false
    private var lifecycleObservers: [NSObjectProtocol] = []

    private static let titleBodyGapSeconds: Double = 2
    private static let betweenStoriesGapSeconds: Double = 3

    private init() {
        let saved = UserDefaults.standard.object(forKey: Self.rateKey) as? Float
        // 没设过时用稍慢，睡前更好听
        playbackRate = saved ?? 0.85
        lastStoryId = UserDefaults.standard.string(forKey: Self.lastIdKey)
        if let data = UserDefaults.standard.data(forKey: Self.lastByShelfKey),
           let map = try? JSONDecoder().decode([String: String].self, from: data)
        {
            lastStoryIdByShelf = map
        }
        migrateGlobalLastIfNeeded()
        titleBridge.owner = self
        titleSynth.delegate = titleBridge
        observeInterruptions()
        observeAppLifecycle()
    }

    /// 目录加载后再调一次：把旧的全局「上次听」写进对应书架
    func migrateGlobalLastIfNeeded() {
        guard let id = lastStoryId,
              let story = BedtimeCatalogStore.shared.story(id: id)
        else { return }
        let key = Self.shelfKey(ageId: story.ageId, shelfId: story.shelfId)
        guard lastStoryIdByShelf[key] == nil else { return }
        lastStoryIdByShelf[key] = id
        persistLastByShelf()
    }

    static func shelfKey(ageId: String, shelfId: String) -> String {
        "\(ageId)|\(shelfId)"
    }

    /// 该年龄×书架上次听到的故事（仍在目录里且有声音才返回）
    func resumeStory(ageId: String, shelfId: String) -> BedtimeStory? {
        let key = Self.shelfKey(ageId: ageId, shelfId: shelfId)
        guard let id = lastStoryIdByShelf[key] ?? (lastStoryId.flatMap { lid in
            BedtimeCatalogStore.shared.story(id: lid).flatMap { s in
                s.ageId == ageId && s.shelfId == shelfId ? lid : nil
            }
        }) else { return nil }
        guard let story = BedtimeCatalogStore.shared.story(id: id), hasAudio(for: id) else { return nil }
        return story
    }

    /// 从该类别上次进度继续听
    func continueShelf(ageId: String, shelfId: String) {
        guard let story = resumeStory(ageId: ageId, shelfId: shelfId) else { return }
        let queue = BedtimeCatalogStore.shared.playQueue(for: story)
        play(story, queue: queue)
    }

    func hasAudio(for storyId: String) -> Bool {
        BedtimeRemoteAudio.hasBody(storyId)
    }

    func audioURL(for storyId: String) -> URL? {
        BedtimeRemoteAudio.resolveBodyURL(storyId)
    }

    /// 火山录的「请听，标题」短音频（可云端）
    func titleAudioURL(for storyId: String) -> URL? {
        BedtimeRemoteAudio.resolveTitleURL(storyId)
    }

    func toggle(_ story: BedtimeStory, queue: [BedtimeStory]? = nil) {
        if playingId == story.id, isPlaying {
            pause()
        } else if playingId == story.id, !isPlaying {
            resume()
        } else {
            play(story, queue: queue)
        }
    }

    func play(_ story: BedtimeStory, queue: [BedtimeStory]? = nil) {
        // 会员未开通且超出免费试听时不播（商店商品未上架则不拦截）
        guard MembershipStore.shared.canPlay(story) else {
            MembershipStore.shared.showPaywall = true
            return
        }
        if let queue {
            self.queue = queue.filter { hasAudio(for: $0.id) && MembershipStore.shared.canPlay($0) }
        } else if self.queue.isEmpty || !self.queue.contains(where: { $0.id == story.id }) {
            self.queue = hasAudio(for: story.id) ? [story] : []
        }
        guard let bodyURL = audioURL(for: story.id) else { return }
        tearDownPlayer()
        activatePlaybackSession()
        setupRemoteCommandsIfNeeded()
        pendingBodyURL = bodyURL
        playingId = story.id
        rememberLast(story.id)
        isPlaying = true
        updateNowPlaying(for: story)

        if let titleURL = titleAudioURL(for: story.id) {
            // 标题音频念「请听，标题」
            usingTitleMp3 = true
            isAnnouncingTitle = true
            waitingToStartBody = true
            attachPlayer(url: titleURL, announceTitle: true, storyId: story.id, isTitle: true)
            player?.playImmediately(atRate: playbackRate)
        } else if Self.bodyAlreadyAnnouncesTitle(story) {
            // 腾讯云相声版：正文开头已念系列名和标题，不再系统重念
            usingTitleMp3 = false
            isAnnouncingTitle = false
            waitingToStartBody = false
            pendingBodyURL = nil
            attachPlayer(url: bodyURL, announceTitle: false, storyId: story.id, isTitle: false)
            player?.playImmediately(atRate: playbackRate)
        } else {
            // 还没录标题时，系统先念「请听，标题」
            usingTitleMp3 = false
            attachPlayer(url: bodyURL, announceTitle: false, storyId: story.id, isTitle: false)
            speakTitleThenStartBody("请听，\(story.title)")
        }
    }

    /// 正文音频开头已含「请听…第N集…」时，跳过系统标题朗读。
    private static func bodyAlreadyAnnouncesTitle(_ story: BedtimeStory) -> Bool {
        story.shelfId == "treasure" || story.shelfId == "safety"
            || story.id.hasPrefix("X") || story.id.hasPrefix("Z")
    }

    func pause() {
        cancelGapTask()
        resumeAfterInterruption = false
        if isAnnouncingTitle, !usingTitleMp3 {
            titleSynth.pauseSpeaking(at: .word)
            isPlaying = false
            refreshNowPlayingElapsed(rate: 0)
            return
        }
        player?.pause()
        isPlaying = false
        refreshNowPlayingElapsed(rate: 0)
    }

    func resume() {
        activatePlaybackSession()
        if isAnnouncingTitle, !usingTitleMp3 {
            if titleSynth.isPaused {
                titleSynth.continueSpeaking()
            } else if waitingToStartBody, let story = nowPlayingStory {
                speakTitleThenStartBody("请听，\(story.title)")
            }
            isPlaying = true
            refreshNowPlayingElapsed()
            return
        }
        if waitingToStartBody, !isAnnouncingTitle {
            // 标题已念完，停在开篇等待里
            isPlaying = true
            scheduleStartBody(after: Self.titleBodyGapSeconds)
            refreshNowPlayingElapsed()
            return
        }
        guard player != nil else { return }
        player?.rate = playbackRate
        isPlaying = true
        refreshNowPlayingElapsed()
    }

    var hasNowPlaying: Bool {
        playingId != nil && (player != nil || isAnnouncingTitle)
    }

    /// 导航栏：正在播→暂停；已暂停→继续；没有会话→重播上次那篇。
    var canControlPlayback: Bool {
        if hasNowPlaying { return true }
        if let id = lastStoryId, hasAudio(for: id) { return true }
        return false
    }

    /// 歌单式标题：正在播或上次听过的那篇。
    /// 正文播放进度 0…1（漫画翻格用）。标题段或未知时长时为 0。
    var bodyProgress: Double {
        guard !isAnnouncingTitle, let player, let item = player.currentItem else { return 0 }
        var duration = item.duration.seconds
        if !duration.isFinite || duration <= 1 {
            duration = item.asset.duration.seconds
        }
        guard duration.isFinite, duration > 1 else { return 0 }
        let elapsed = player.currentTime().seconds
        guard elapsed.isFinite, elapsed >= 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    var nowPlayingStory: BedtimeStory? {
        let id = playingId ?? lastStoryId
        guard let id else { return nil }
        return BedtimeCatalogStore.shared.story(id: id)
    }

    func togglePauseResume() {
        if isPlaying {
            pause()
            return
        }
        if player != nil || isAnnouncingTitle {
            resume()
            return
        }
        resumeLastStory()
    }

    /// 休息页专用队列：护眼知识最先，再一般知识，再故事，再人物。
    func makeRestListeningQueue() -> [BedtimeStory] {
        let withAudio = BedtimeCatalogStore.shared.stories.filter { hasAudio(for: $0.id) }
        let knowledge = withAudio.filter { $0.shelfId == "knowledge" }
        let eyeCare = knowledge.filter { Self.isEyeCareContent($0) }
        let otherKnowledge = knowledge.filter { !Self.isEyeCareContent($0) }
        let fairy = withAudio.filter { $0.shelfId == "fairy" }
        let biography = withAudio.filter { $0.shelfId == "biography" }
        let treasure = withAudio.filter { $0.shelfId == "treasure" }
        let safety = withAudio.filter { $0.shelfId == "safety" }
        return eyeCare + otherKnowledge + fairy + biography + treasure + safety
    }

    private static func isEyeCareContent(_ story: BedtimeStory) -> Bool {
        let title = story.title
        if title.contains("眼") || title.contains("20-20-20") || title.contains("远望") {
            return true
        }
        // 开头几句里讲眼睛的也算护眼
        let head = String(story.text.prefix(80))
        return head.contains("眼睛") || head.contains("眨眼") || head.contains("揉眼")
    }

    /// 休息页点播放：用火山录音，护眼内容排最前。
    func playRestListening() {
        let q = makeRestListeningQueue()
        guard !q.isEmpty else { return }
        let start: BedtimeStory
        if let id = playingId ?? lastStoryId, let hit = q.first(where: { $0.id == id }) {
            start = hit
        } else {
            start = q[0]
        }
        play(start, queue: q)
    }

    func toggleRestListening() {
        if hasNowPlaying {
            togglePauseResume()
        } else {
            playRestListening()
        }
    }

    func playRestNext() {
        let q = makeRestListeningQueue()
        guard !q.isEmpty else { return }
        queue = q
        if let id = playingId ?? lastStoryId, let idx = q.firstIndex(where: { $0.id == id }) {
            let next = idx + 1 < q.count ? q[idx + 1] : q[0]
            play(next, queue: q)
        } else {
            play(q[0], queue: q)
        }
    }

    /// 从上次听的那篇接着播（从头播该篇，并带上同书架队列）。
    func resumeLastStory() {
        guard let id = lastStoryId,
              let story = BedtimeCatalogStore.shared.story(id: id),
              hasAudio(for: id)
        else { return }
        play(story, queue: BedtimeCatalogStore.shared.playQueue(for: story))
    }

    /// 当前语速按钮上的中文名。
    var rateLabel: String {
        Self.rateOptions.first { abs($0.rate - playbackRate) < 0.01 }?.label ?? "正常"
    }

    /// 按慢 → 稍慢 → 正常 → 稍快 循环。
    func cyclePlaybackRate() {
        let rates = Self.rateOptions.map(\.rate)
        let idx = rates.firstIndex { abs($0 - playbackRate) < 0.01 } ?? 1
        playbackRate = rates[(idx + 1) % rates.count]
    }

    var canPlayPrevious: Bool {
        guard let id = playingId ?? lastStoryId else { return false }
        ensureQueueForCurrentIfNeeded()
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return false }
        return idx > 0
    }

    var canPlayNext: Bool {
        guard let id = playingId ?? lastStoryId else { return false }
        ensureQueueForCurrentIfNeeded()
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return false }
        return idx + 1 < queue.count
    }

    func playPrevious() {
        ensureQueueForCurrentIfNeeded()
        let id = playingId ?? lastStoryId
        guard let id, let idx = queue.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        play(queue[idx - 1])
    }

    func playNext() {
        ensureQueueForCurrentIfNeeded()
        let id = playingId ?? lastStoryId
        guard let id, let idx = queue.firstIndex(where: { $0.id == id }), idx + 1 < queue.count else { return }
        play(queue[idx + 1])
    }

    /// 只有 lastStoryId、队列空时，补上同书架可听队列。
    private func ensureQueueForCurrentIfNeeded() {
        guard queue.isEmpty, let id = playingId ?? lastStoryId,
              let story = BedtimeCatalogStore.shared.story(id: id)
        else { return }
        queue = BedtimeCatalogStore.shared.playQueue(for: story).filter { hasAudio(for: $0.id) }
    }

    private func rememberLast(_ id: String) {
        lastStoryId = id
        UserDefaults.standard.set(id, forKey: Self.lastIdKey)
        if let story = BedtimeCatalogStore.shared.story(id: id) {
            lastStoryIdByShelf[Self.shelfKey(ageId: story.ageId, shelfId: story.shelfId)] = id
            persistLastByShelf()
        }
    }

    private func persistLastByShelf() {
        if let data = try? JSONEncoder().encode(lastStoryIdByShelf) {
            UserDefaults.standard.set(data, forKey: Self.lastByShelfKey)
        }
    }

    func stop() {
        resumeAfterInterruption = false
        stopTitleSpeech()
        tearDownPlayer()
        playingId = nil
        isPlaying = false
        queue = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        releaseSessionIfIdle()
    }

    /// 没有在播时交还音频会话，避免切到浏览器/抖音后整机没声音。
    func releaseSessionIfIdle() {
        guard !isPlaying, !resumeAfterInterruption, !isAnnouncingTitle, !waitingToStartBody else { return }
        guard player == nil else { return }
        guard !RestStoryPlayer.shared.isSpeaking, !RestStoryPlayer.shared.isPaused else { return }
        forceYieldAudioSession()
    }

    /// 强制交还系统声音（没在播时调用）。iPad 有时占着会话，别的 App / 系统提示就没声。
    func forceYieldAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func playNextAfterEnd() {
        guard let id = playingId,
              let idx = queue.firstIndex(where: { $0.id == id })
        else {
            stop()
            return
        }
        let nextIndex = idx + 1
        guard nextIndex < queue.count else {
            stop()
            return
        }
        let next = queue[nextIndex]
        cancelGapTask()
        // 一篇听完，停 3 秒再念下一篇标题
        gapTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.betweenStoriesGapSeconds))
            guard !Task.isCancelled else { return }
            guard self.playingId == id, self.isPlaying else { return }
            self.play(next)
        }
    }

    private func tearDownPlayer() {
        cancelGapTask()
        stopTitleSpeech()
        pendingBodyURL = nil
        usingTitleMp3 = false
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
    }

    private func attachPlayer(url: URL, announceTitle: Bool, storyId: String? = nil, isTitle: Bool = false) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        // 云端流式需要等待缓冲；本地文件可立刻播
        let remote = url.scheme == "http" || url.scheme == "https"
        avPlayer.automaticallyWaitsToMinimizeStalling = remote
        player = avPlayer
        if remote, let storyId {
            BedtimeRemoteAudio.prefetchToCache(remote: url, storyId: storyId, isTitle: isTitle)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if announceTitle {
                    self.titleMp3DidFinish()
                } else {
                    self.playNextAfterEnd()
                }
            }
        }
    }

    private func speakTitleThenStartBody(_ title: String) {
        cancelGapTask()
        if titleSynth.isSpeaking || titleSynth.isPaused {
            titleSynth.stopSpeaking(at: .immediate)
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            waitingToStartBody = false
            isAnnouncingTitle = false
            startBodyAudio()
            return
        }
        isAnnouncingTitle = true
        waitingToStartBody = true
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            ?? AVSpeechSynthesisVoice(language: "zh-Hans")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.88
        utterance.preUtteranceDelay = 0.12
        utterance.postUtteranceDelay = 0
        titleSynth.speak(utterance)
    }

    private func stopTitleSpeech() {
        // 不要在这里 cancelGapTask：正文前的 2 秒等待也靠 gapTask
        waitingToStartBody = false
        isAnnouncingTitle = false
        if titleSynth.isSpeaking || titleSynth.isPaused {
            titleSynth.stopSpeaking(at: .immediate)
        }
    }

    private func titleMp3DidFinish() {
        guard waitingToStartBody else { return }
        isAnnouncingTitle = false
        guard isPlaying else { return }
        scheduleStartBody(after: Self.titleBodyGapSeconds)
    }

    fileprivate func titleSpeechDidFinish() {
        guard waitingToStartBody else { return }
        isAnnouncingTitle = false
        guard isPlaying || resumeAfterInterruption else { return }
        isPlaying = true
        // 念完标题，等 2 秒再播正文
        scheduleStartBody(after: Self.titleBodyGapSeconds)
    }

    fileprivate func titleSpeechDidCancel() {
        guard waitingToStartBody, isAnnouncingTitle, !usingTitleMp3 else { return }
        isAnnouncingTitle = false
        waitingToStartBody = false
        guard isPlaying || resumeAfterInterruption else { return }
        isPlaying = true
        resumeAfterInterruption = false
        activatePlaybackSession()
        startBodyAudio()
    }

    private func scheduleStartBody(after seconds: Double) {
        cancelGapTask()
        gapTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            guard self.waitingToStartBody, self.isPlaying else { return }
            self.waitingToStartBody = false
            self.startBodyAudio()
        }
    }

    private func cancelGapTask() {
        gapTask?.cancel()
        gapTask = nil
    }

    private func startBodyAudio() {
        guard let bodyURL = pendingBodyURL else { return }
        usingTitleMp3 = false
        isAnnouncingTitle = false
        attachPlayer(url: bodyURL, announceTitle: false, storyId: playingId, isTitle: false)
        player?.playImmediately(atRate: playbackRate)
        refreshNowPlayingElapsed()
    }

    /// 熄屏 / 切后台仍继续播：playback 类别 + Info.plist 的 audio 后台模式。
    private func activatePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // 先松一下再占，避免上次会话卡住导致整机没声
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            // default 模式比 spokenAudio 更稳，锁屏后系统更愿意继续播
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            // 再试一次宽松选项
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
        }
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }
    }

    /// 熄屏进后台时再声明一次会话，并踢一下播放器（防 rate 被置 0）。
    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        func kick(_ _: Notification) {
            Task { @MainActor in
                BedtimeAudioPlayer.shared.keepPlayingInBackgroundIfNeeded()
            }
        }
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main, using: kick),
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: kick),
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: kick),
        ]
    }

    private func keepPlayingInBackgroundIfNeeded() {
        // 没在播：回到前台时交还会话，恢复系统/别的 App 声音
        guard isPlaying || resumeAfterInterruption else {
            releaseSessionIfIdle()
            return
        }
        activatePlaybackSession()
        setupRemoteCommandsIfNeeded()
        if isAnnouncingTitle, !usingTitleMp3 {
            if titleSynth.isPaused {
                titleSynth.continueSpeaking()
            } else if !titleSynth.isSpeaking, waitingToStartBody {
                // 系统朗读标题被熄屏掐断：直接播正文，别卡住
                waitingToStartBody = false
                isAnnouncingTitle = false
                startBodyAudio()
            }
            refreshNowPlayingElapsed()
            return
        }
        if waitingToStartBody, !isAnnouncingTitle {
            // 标题已完、正在等 2 秒：保持 isPlaying，等 gapTask 自己开正文
            refreshNowPlayingElapsed()
            return
        }
        guard let player else { return }
        if player.timeControlStatus != .playing {
            player.playImmediately(atRate: playbackRate)
        } else {
            player.rate = playbackRate
        }
        isPlaying = true
        resumeAfterInterruption = false
        refreshNowPlayingElapsed()
    }

    private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        switch type {
        case .began:
            // 不要把 isPlaying 打成 false：否则标题后的等待、篇间等待会永远不再开播
            guard isPlaying || player?.timeControlStatus == .playing || titleSynth.isSpeaking else { return }
            resumeAfterInterruption = true
            if isAnnouncingTitle, !usingTitleMp3 {
                titleSynth.pauseSpeaking(at: .word)
            } else {
                player?.pause()
            }
            refreshNowPlayingElapsed(rate: 0)
        case .ended:
            let raw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: raw)
            // 熄屏有时不带 shouldResume；只要打断前在播就接着播
            guard resumeAfterInterruption || options.contains(.shouldResume) else { return }
            resumeAfterInterruption = false
            activatePlaybackSession()
            if player != nil || isAnnouncingTitle || waitingToStartBody {
                if !isPlaying { isPlaying = true }
                resume()
                keepPlayingInBackgroundIfNeeded()
            }
        @unknown default:
            break
        }
    }

    private func setupRemoteCommandsIfNeeded() {
        guard !didSetupRemote else { return }
        didSetupRemote = true
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePauseResume() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }
    }

    private func updateNowPlaying(for story: BedtimeStory) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: story.title,
            MPMediaItemPropertyArtist: "眼睛闹钟 · 语音书架",
            MPNowPlayingInfoPropertyPlaybackRate: Double(isPlaying ? playbackRate : 0),
        ]
        if let item = player?.currentItem {
            let duration = item.asset.duration.seconds
            if duration.isFinite, duration > 0 {
                info[MPMediaItemPropertyPlaybackDuration] = duration
            }
            let elapsed = player?.currentTime().seconds ?? 0
            if elapsed.isFinite {
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func refreshNowPlayingElapsed(rate: Float? = nil) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        let elapsed = player?.currentTime().seconds ?? 0
        if elapsed.isFinite {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = Double(rate ?? (isPlaying ? playbackRate : 0))
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

private final class TitleSpeechBridge: NSObject, AVSpeechSynthesizerDelegate {
    weak var owner: BedtimeAudioPlayer?

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.owner?.titleSpeechDidFinish()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            // 熄屏常会取消系统朗读标题：跳过标题，直接播正文
            self.owner?.titleSpeechDidCancel()
        }
    }
}

enum BedtimeAge: String, CaseIterable, Identifiable {
    case child = "儿童类"
    case youth = "少年类"

    var id: String { rawValue }

    /// 界面副标题用的年龄范围
    var ageRange: String {
        switch self {
        case .child: "3–10岁"
        case .youth: "11–15岁"
        }
    }

    var hint: String {
        switch self {
        case .child: "3–10岁。知识讲清楚，故事轻轻讲，还有人物小传。"
        case .youth: "11–15岁。道理更深一点，仍短、仍清楚；人物传记可对照自己怎么选。"
        }
    }

    /// 目录 JSON 里的年龄键（含旧键迁移）
    var catalogKey: String {
        switch self {
        case .child: "child"
        case .youth: "youth"
        }
    }
}

/// 书架上的书
enum BedtimeShelf: String, CaseIterable, Identifiable {
    case knowledge = "光光讲知识"
    case fairy = "光光睡前小故事"
    case biography = "光光讲人物"
    case treasure = "光光去寻宝"
    case safety = "光光安全小剧场"

    var id: String { rawValue }

    var catalogKey: String {
        switch self {
        case .knowledge: "knowledge"
        case .fairy: "fairy"
        case .biography: "biography"
        case .treasure: "treasure"
        case .safety: "safety"
        }
    }

    var badge: String {
        switch self {
        case .knowledge: "知识"
        case .fairy: "故事"
        case .biography: "人物"
        case .treasure: "地理"
        case .safety: "安全"
        }
    }

    var badgeLines: String { badge }

    /// 书架左侧书皮图（有图则用系统字叠主名）
    var coverImageName: String? {
        switch self {
        case .knowledge: "ShelfKnowledge"
        case .fairy: "ShelfFairy"
        case .biography: "ShelfBiography"
        case .treasure: "ShelfGeography"
        case .safety: "ShelfSafety"
        }
    }

    /// 书皮上的主标题
    var coverTitle: String? {
        badge
    }

    var blurb: String {
        switch self {
        case .knowledge: "常见为什么，讲对、讲清楚。轻改写成睡前能听完的短篇。"
        case .fairy: "公版童话寓言轻改：保留情节核，句子新写，软化吓人处。"
        case .biography: "科学家与历史人物小传。史实概述，句子原创，不抄别人传记。"
        case .treasure: "光光和小问相声对口，一省一集寻知识宝。已有三季。"
        case .safety: "光光和小问相声对口，生活安全小规矩。已有三季。"
        }
    }

    var catalogFooter: String {
        switch self {
        case .knowledge: "常识科普，句子原创，不摘录受版权保护的读物。"
        case .fairy: "公版故事只借情节核，句子新写，并软化吓人处。"
        case .biography: "人物小传按史实概述，句子原创，不抄别人的传记书。"
        case .treasure: "原创对口相声，地理小知识，不抄市面寻宝漫画。"
        case .safety: "生活安全提醒，有趣好记，不吓人。"
        }
    }
}

/// 睡前小故事里的子目录（名字后带来历，方便找）
enum FairyGroup: String, CaseIterable, Identifiable, Hashable {
    case cnMythLegend = "cn_myth_legend"
    case cnFableStory = "cn_fable_story"
    case foreign = "foreign"
    case original = "original"

    var id: String { rawValue }

    /// 主标题
    var title: String {
        switch self {
        case .cnMythLegend: "中国 · 神话·传说"
        case .cnFableStory: "中国 · 寓言·故事"
        case .foreign: "国外 · 寓言·童话·传说"
        case .original: "原创 · 思辨小故事"
        }
    }

    /// 来历说明（跟在分类后面，方便寻找）
    var originNote: String {
        switch self {
        case .cnMythLegend: "神话、民间与戏曲传说"
        case .cnFableStory: "成语寓言、史传典故"
        case .foreign: "伊索、格林、安徒生、世界民间"
        case .original: "新写寓言，非公版改编"
        }
    }

    var badge: String {
        switch self {
        case .cnMythLegend: "神话"
        case .cnFableStory: "寓言"
        case .foreign: "国外"
        case .original: "原创"
        }
    }
}

struct BedtimeStory: Identifiable, Hashable, Sendable {
    var id: String
    /// 目录里的年龄键，如 child / youth（也可以后扩展）
    var ageId: String
    /// 目录里的书架键，如 knowledge / fairy / novel
    var shelfId: String
    var title: String
    var text: String
    /// 子目录键（如睡前故事分组）；没有则为 nil
    var fairyGroupId: String?
    /// 展示用标题（随目录一起写入，避免运行时查表）
    var ageTitle: String
    var shelfTitle: String
    var ageRangeText: String

    /// 兼容旧枚举逻辑（未知分类时为 nil）
    var age: BedtimeAge? {
        switch ageId {
        case "child", "kindergarten", "primary": return .child
        case "youth", "junior": return .youth
        default: return nil
        }
    }

    var shelf: BedtimeShelf? {
        BedtimeShelf.allCases.first { $0.catalogKey == shelfId }
    }

    var fairyGroup: FairyGroup? {
        fairyGroupId.flatMap { FairyGroup(rawValue: $0) }
    }
}

/// 寻宝/安全/知识/故事/人物漫画：只装带字版，按故事编号取三宫格。
enum BedtimeComics {
    /// 儿童类 X001 与少年类 X101 共用同一套图；G/S/B 直接用编号文件夹。
    static func folderId(for storyId: String) -> String {
        guard let letter = storyId.first,
              let n = Int(storyId.dropFirst())
        else { return storyId }
        if letter == "X" || letter == "Z" {
            return String(format: "%@%03d", String(letter), n % 100)
        }
        return storyId
    }

    static func panelURLs(for storyId: String) -> [URL] {
        let folder = folderId(for: storyId)
        // 按篇幅最多 10 格；寻宝/安全多为 3 格
        return (1 ... 10).compactMap { i in
            Bundle.main.url(
                forResource: String(format: "%02d", i),
                withExtension: "jpg",
                subdirectory: "BedtimeComics/\(folder)"
            )
        }
    }

    static func hasComics(for storyId: String) -> Bool {
        !panelURLs(for: storyId).isEmpty
    }
}

@MainActor
enum BedtimeLibrary {
    static var all: [BedtimeStory] { BedtimeCatalogStore.shared.stories }

    static func stories(for age: BedtimeAge, shelf: BedtimeShelf) -> [BedtimeStory] {
        BedtimeCatalogStore.shared.stories(ageId: age.catalogKey, shelfId: shelf.catalogKey)
    }

    static func stories(for age: BedtimeAge, shelf: BedtimeShelf, group: FairyGroup) -> [BedtimeStory] {
        BedtimeCatalogStore.shared.stories(
            ageId: age.catalogKey,
            shelfId: shelf.catalogKey,
            groupId: group.rawValue
        )
    }

    static func playQueue(for story: BedtimeStory) -> [BedtimeStory] {
        BedtimeCatalogStore.shared.playQueue(for: story)
    }

    static func stories(for age: BedtimeAge) -> [BedtimeStory] {
        BedtimeCatalogStore.shared.stories.filter { $0.ageId == age.catalogKey }
    }
}
