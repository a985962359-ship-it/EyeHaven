import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class RestStoryPlayer {
    static let shared = RestStoryPlayer()

    private(set) var current: RestStory?
    private(set) var isSpeaking = false
    private(set) var isPaused = false

    private let synthesizer = AVSpeechSynthesizer()
    private let bridge = SpeechBridge()
    private var pieces: [SpokenPiece] = []
    private var nextIndex = 0
    private var lastStoryId: String?
    private var enabled = false
    private var shouldContinue = false
    private var speakToken = 0
    private var pauseTask: Task<Void, Never>?
    private var lastSpokenPause: TimeInterval = 0
    private var interruptionObserver: NSObjectProtocol?

    private static let lastStoryKey = "rest.story.lastId"
    private static let pieceKey = "rest.story.nextIndex"

    private init() {
        bridge.owner = self
        synthesizer.delegate = bridge
        lastStoryId = UserDefaults.standard.string(forKey: Self.lastStoryKey)
        nextIndex = UserDefaults.standard.integer(forKey: Self.pieceKey)
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

    private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        switch type {
        case .began:
            guard isSpeaking, !isPaused else { return }
            pauseTask?.cancel()
            pauseTask = nil
            synthesizer.pauseSpeaking(at: .word)
            isPaused = true
            isSpeaking = false
        case .ended:
            let raw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: raw)
            guard options.contains(.shouldResume), enabled, isPaused, current != nil else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            isPaused = false
            isSpeaking = true
            if synthesizer.isSpeaking {
                synthesizer.continueSpeaking()
            } else {
                speakNextParagraph()
            }
        @unknown default:
            break
        }
    }

    func apply(enabled: Bool) {
        self.enabled = enabled
        if !enabled {
            stop()
        }
    }

    /// Start a story if nothing is already playing. Safe to call again after a lock/unlock.
    func startIfNeeded() {
        guard enabled else { return }
        if isSpeaking || isPaused { return }
        if let id = lastStoryId, let story = RestStoryLibrary.story(id: id) {
            let saved = Self.spokenPieces(from: story)
            if nextIndex < saved.count {
                play(story, from: nextIndex)
                return
            }
        }
        play(RestStoryLibrary.next(after: lastStoryId))
    }

    func togglePause() {
        guard current != nil else {
            startIfNeeded()
            return
        }
        if isPaused {
            isPaused = false
            isSpeaking = true
            if synthesizer.isSpeaking {
                synthesizer.continueSpeaking()
            } else {
                speakNextParagraph()
            }
        } else if synthesizer.isSpeaking || isSpeaking {
            pauseTask?.cancel()
            pauseTask = nil
            synthesizer.pauseSpeaking(at: .word)
            isPaused = true
            isSpeaking = false
        } else {
            startIfNeeded()
        }
    }

    func playNext() {
        guard enabled else { return }
        play(RestStoryLibrary.next(after: current?.id ?? lastStoryId), from: 0)
    }

    func stop() {
        speakToken += 1
        shouldContinue = false
        pauseTask?.cancel()
        pauseTask = nil
        synthesizer.stopSpeaking(at: .immediate)
        persistProgress()
        pieces = []
        isSpeaking = false
        isPaused = false
        current = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    fileprivate func utteranceDidFinish() {
        guard shouldContinue, current != nil, !isPaused else { return }
        persistProgress()
        waitThenSpeakNext()
    }

    private func play(_ story: RestStory, from index: Int = 0) {
        guard enabled else { return }
        speakToken += 1
        let token = speakToken
        shouldContinue = false
        pauseTask?.cancel()
        pauseTask = nil
        synthesizer.stopSpeaking(at: .immediate)
        current = story
        lastStoryId = story.id
        pieces = Self.spokenPieces(from: story)
        nextIndex = min(max(0, index), pieces.count)
        persistProgress()
        isPaused = false
        lastSpokenPause = 0
        activateSession()
        Task { @MainActor in
            guard token == self.speakToken else { return }
            self.shouldContinue = true
            self.speakNextParagraph()
        }
    }

    private func waitThenSpeakNext() {
        guard shouldContinue, current != nil, !isPaused else { return }
        let token = speakToken
        let pause = lastSpokenPause
        pauseTask?.cancel()
        pauseTask = Task { @MainActor in
            if pause > 0 {
                try? await Task.sleep(for: .seconds(pause))
            }
            guard token == self.speakToken, self.shouldContinue, !self.isPaused else { return }
            self.speakNextParagraph()
        }
    }

    private func persistProgress() {
        if let lastStoryId {
            UserDefaults.standard.set(lastStoryId, forKey: Self.lastStoryKey)
        }
        UserDefaults.standard.set(nextIndex, forKey: Self.pieceKey)
    }

    private func speakNextParagraph() {
        guard shouldContinue else { return }
        guard nextIndex < pieces.count else {
            isSpeaking = false
            playNext()
            return
        }
        let piece = pieces[nextIndex]
        nextIndex += 1
        lastSpokenPause = piece.pause
        persistProgress()
        let utterance = AVSpeechUtterance(string: piece.text)
        utterance.voice = Self.bestChineseVoice()
        // Apple's 0.5 is conversational; storytelling needs more air.
        utterance.rate = 0.27
        utterance.pitchMultiplier = 0.94
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        isSpeaking = true
        isPaused = false
        synthesizer.speak(utterance)
    }

    /// Prefer a downloaded Premium/Enhanced Chinese voice over the compact default.
    private static func bestChineseVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.hasPrefix("zh")
        }
        let ranked = voices.sorted { a, b in
            voiceScore(a) > voiceScore(b)
        }
        return ranked.first
            ?? AVSpeechSynthesisVoice(language: "zh-CN")
            ?? AVSpeechSynthesisVoice(language: "zh-Hans")
    }

    private static func voiceScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        var score = 0
        switch voice.quality {
        case .premium: score += 300
        case .enhanced: score += 200
        default: score += 10
        }
        if voice.language == "zh-CN" { score += 40 }
        else if voice.language.hasPrefix("zh-Hans") { score += 30 }
        else if voice.language.hasPrefix("zh") { score += 10 }
        let id = voice.identifier.lowercased()
        if id.contains("siri") { score += 50 }
        if id.contains("premium") { score += 40 }
        if id.contains("enhanced") { score += 20 }
        if id.contains("compact") { score -= 30 }
        if voice.gender == .female { score += 8 }
        return score
    }

    private static func spokenPieces(from story: RestStory) -> [SpokenPiece] {
        var result: [SpokenPiece] = []
        for (index, paragraph) in story.paragraphs.enumerated() {
            let clauses = splitForRhythm(paragraph)
            for (clauseIndex, clause) in clauses.enumerated() {
                let isLastInParagraph = clauseIndex == clauses.count - 1
                let isLastParagraph = index == story.paragraphs.count - 1
                let pause: TimeInterval
                if isLastInParagraph && isLastParagraph {
                    pause = 5.2
                } else if isLastInParagraph {
                    pause = 4.5
                } else if clause.hasSuffix("。") {
                    pause = 3.0
                } else if clause.hasSuffix("！") || clause.hasSuffix("？") {
                    pause = 2.6
                } else {
                    pause = 2.0
                }
                result.append(SpokenPiece(text: clause, pause: pause))
            }
        }
        return result
    }

    private static func splitForRhythm(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if "。！？".contains(character) {
                let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { sentences.append(piece) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }

        return sentences.flatMap { sentence in
            guard sentence.count >= 28 else { return [sentence] }
            return splitLongSentence(sentence)
        }
    }

    private static func splitLongSentence(_ sentence: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for character in sentence {
            current.append(character)
            if "，、；".contains(character), current.count >= 18 {
                let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { parts.append(piece) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { parts.append(tail) }
        return parts.isEmpty ? [sentence] : parts
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }
}

private struct SpokenPiece {
    var text: String
    var pause: TimeInterval
}

private final class SpeechBridge: NSObject, AVSpeechSynthesizerDelegate {
    weak var owner: RestStoryPlayer?

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.owner?.utteranceDidFinish()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        // stopSpeaking / 换一则 must not advance the story.
    }
}
