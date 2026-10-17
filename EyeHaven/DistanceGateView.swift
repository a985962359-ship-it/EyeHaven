import ARKit
import AVFoundation
import SceneKit
import SwiftUI

struct DistanceGateView: View {
    var thresholdCm: Int
    var onPass: () -> Void
    var onCancel: () -> Void

    private static let adjustPrompt = "请先调整一下屏幕距离哦"
    private static let passPrompt = "这样就很好啦，保持这个距离用吧，眼睛会更舒服。"

    @State private var checker = DistanceChecker()
    @State private var didPass = false
    @State private var abandoned = false
    @State private var showingSuccessHold = false
    @State private var guangguangTalking = false
    @State private var passSpeaker = DistancePromptPlayer()
    @State private var didPlayAdjust = false

    var body: some View {
        ZStack {
            if showingSuccessHold {
                successBackground
                successContent
            } else {
                Palette.dusk.ignoresSafeArea()
                cameraLayer
                measuringContent
            }
        }
        .onAppear {
            checker.start(thresholdCm: thresholdCm)
            playAdjustPromptIfNeeded()
        }
        .onDisappear {
            abandoned = true
            passSpeaker.stop()
            checker.stop()
        }
        .onChange(of: checker.status) { _, newValue in
            switch newValue {
            case .noFace, .reading, .starting:
                playAdjustPromptIfNeeded()
            case .ready:
                if !didPass, !abandoned, !showingSuccessHold {
                    beginSuccessHold()
                }
            default:
                break
            }
        }
    }

    private var successBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.88, green: 0.95, blue: 0.90),
                Palette.mist,
                Color(red: 0.93, green: 0.96, blue: 0.98),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var successContent: some View {
        VStack(spacing: HavenLayout.isPad ? 28 : 22) {
            Text("测距通过")
                .font(HavenLayout.isPad ? .title.weight(.semibold) : .title2.weight(.semibold))
                .foregroundStyle(Palette.dusk)

            DistanceGuangguang(talking: guangguangTalking, size: HavenLayout.isPad ? 220 : 180)

            Text(Self.passPrompt)
                .font(HavenLayout.isPad ? .title3.weight(.semibold) : .title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.pine)
                .padding(.horizontal, 32)
        }
        .padding(HavenLayout.isPad ? 36 : 24)
        .frame(maxWidth: HavenLayout.pageMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var measuringContent: some View {
        VStack(spacing: HavenLayout.isPad ? 24 : 20) {
            Text("开始前测一次距离")
                .font(HavenLayout.isPad ? .title.weight(.semibold) : .title2.weight(.semibold))
                .foregroundStyle(Palette.foam)
            Text("\(Self.adjustPrompt)。把脸放进圆圈，坐到大约 \(thresholdCm) 厘米。")
                .font(HavenLayout.isPad ? .title3.weight(.semibold) : .headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.foam)
                .padding(.horizontal, 28)

            ZStack {
                Circle()
                    .stroke(ringColor, lineWidth: 6)
                    .frame(width: HavenLayout.distanceRingSize, height: HavenLayout.distanceRingSize)
                statusText
            }
            .padding(.vertical, 12)

            if case .ready(let cm) = checker.status {
                Text("大约 \(cm) 厘米，可以开始")
                    .font(.headline)
                    .foregroundStyle(Color.green)
            }

            HStack(spacing: 12) {
                Button("取消") {
                    abandoned = true
                    passSpeaker.stop()
                    onCancel()
                }
                .buttonStyle(HavenButtonStyle(filled: false))
                #if targetEnvironment(simulator)
                Button("模拟器跳过") { beginSuccessHold() }
                    .buttonStyle(HavenButtonStyle(filled: true))
                #endif
            }
        }
        .padding(HavenLayout.isPad ? 36 : 16)
        .frame(maxWidth: HavenLayout.pageMaxWidth)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var cameraLayer: some View {
        if ARFaceTrackingConfiguration.isSupported, let session = checker.arSession {
            ARCameraPreview(session: session)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(showingSuccessHold ? 0 : 0.12))
        } else {
            CameraPreview(layer: checker.previewLayer)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(showingSuccessHold ? 0 : 0.15))
        }
    }

    private var ringColor: Color {
        switch checker.status {
        case .ready:
            return Color.green
        case .reading(let cm) where cm >= thresholdCm - 1:
            return Palette.sage
        case .reading:
            return Color.orange.opacity(0.85)
        default:
            return Palette.sage.opacity(0.5)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch checker.status {
        case .starting:
            Text("正在打开摄像头…")
                .foregroundStyle(Palette.foam)
        case .noFace:
            Text("没有看到脸\n请正对屏幕")
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.foam)
        case .reading(let cm):
            VStack(spacing: 6) {
                Text("大约 \(cm) 厘米")
                    .font(.title.weight(.medium))
                    .foregroundStyle(Palette.foam)
                Text(cm >= thresholdCm ? "保持这个距离" : Self.adjustPrompt)
                    .font(.subheadline)
                    .foregroundStyle(cm >= thresholdCm ? Color.green : Color.orange)
            }
        case .ready(let cm):
            Text("\(cm) 厘米")
                .font(.title.weight(.medium))
                .foregroundStyle(Color.green)
        case .unavailable(let message):
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.foam)
                .padding(.horizontal)
        }
    }

    private func playAdjustPromptIfNeeded() {
        guard !didPass, !abandoned, !showingSuccessHold, !didPlayAdjust else { return }
        didPlayAdjust = true
        passSpeaker.play(resource: "adjust")
    }

    private func beginSuccessHold() {
        guard !didPass, !abandoned, !showingSuccessHold else { return }
        showingSuccessHold = true
        guangguangTalking = true
        checker.stop()
        passSpeaker.play(resource: "pass")
        Task { @MainActor in
            // 至少停 3 秒，提示没念完就再等一会儿
            try? await Task.sleep(for: .seconds(3))
            while passSpeaker.isSpeaking, !abandoned {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guangguangTalking = false
            guard !abandoned else { return }
            // 光光说完后再停一下，方便看清
            try? await Task.sleep(for: .milliseconds(400))
            guard !abandoned else { return }
            didPass = true
            onPass()
        }
    }
}

/// 测距成功页：光光说话动画（与故事页同一套图）
private struct DistanceGuangguang: View {
    var talking: Bool
    var size: CGFloat

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

/// 测距提示：播放打包好的腾讯云配音（智甜）
private final class DistancePromptPlayer {
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    var isSpeaking: Bool {
        guard let player else { return false }
        return player.timeControlStatus == .playing
    }

    func play(resource: String) {
        stop()
        guard let url = Self.resolveURL(resource: resource) else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)
        let item = AVPlayerItem(url: url)
        let av = AVPlayer(playerItem: item)
        av.automaticallyWaitsToMinimizeStalling = false
        player = av
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
        av.play()
    }

    func stop() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
        // 测距提示播完必须交还会话，否则切到别的 App 可能没声音
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func resolveURL(resource: String) -> URL? {
        let folders = ["BedtimeAudioBundle/Distance", "BedtimeAudio/Distance", "Distance"]
        let exts = ["mp3", "m4a"]
        for folder in folders {
            for ext in exts {
                if let url = Bundle.main.url(forResource: resource, withExtension: ext, subdirectory: folder) {
                    return url
                }
            }
        }
        for ext in exts {
            if let url = Bundle.main.url(forResource: resource, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}

struct ARCameraPreview: UIViewRepresentable {
    var session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if uiView.session !== session {
            uiView.session = session
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    var layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewHost {
        let view = PreviewHost()
        view.preview = layer
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ uiView: PreviewHost, context: Context) {
        layer.frame = uiView.bounds
    }

    final class PreviewHost: UIView {
        var preview: AVCaptureVideoPreviewLayer?

        override func layoutSubviews() {
            super.layoutSubviews()
            preview?.frame = bounds
        }
    }
}
