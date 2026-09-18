import ARKit
import AVFoundation
import SceneKit
import SwiftUI

struct DistanceGateView: View {
    var thresholdCm: Int
    var onPass: () -> Void
    var onCancel: () -> Void

    @State private var checker = DistanceChecker()
    @State private var didPass = false

    var body: some View {
        ZStack {
            Palette.dusk.ignoresSafeArea()
            cameraLayer
            VStack(spacing: 20) {
                Text("开始前测一次距离")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.foam)
                Text("把脸放进圆圈，坐到大约 \(thresholdCm) 厘米再开始。测完会立刻关掉摄像头。")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.foam.opacity(0.8))
                    .padding(.horizontal, 28)

                ZStack {
                    Circle()
                        .stroke(ringColor, lineWidth: 6)
                        .frame(width: 240, height: 240)
                    statusText
                }
                .padding(.vertical, 12)

                if case .ready(let cm) = checker.status {
                    Text("大约 \(cm) 厘米，可以开始")
                        .font(.headline)
                        .foregroundStyle(Palette.gold)
                }

                HStack(spacing: 12) {
                    Button("取消", action: onCancel)
                        .buttonStyle(HavenButtonStyle(filled: false))
                    #if targetEnvironment(simulator)
                    Button("模拟器跳过") { pass() }
                        .buttonStyle(HavenButtonStyle(filled: true))
                    #endif
                }
            }
            .padding()
        }
        .onAppear {
            checker.start(thresholdCm: thresholdCm)
        }
        .onDisappear {
            checker.stop()
        }
        .onChange(of: checker.status) { _, newValue in
            if case .ready = newValue, !didPass {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    pass()
                }
            }
        }
    }

    @ViewBuilder
    private var cameraLayer: some View {
        if ARFaceTrackingConfiguration.isSupported, let session = checker.arSession {
            ARCameraPreview(session: session)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.12))
        } else {
            CameraPreview(layer: checker.previewLayer)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.15))
        }
    }

    private var ringColor: Color {
        switch checker.status {
        case .ready: Palette.gold
        case .reading(let cm) where cm >= thresholdCm - 1: Palette.sage
        case .reading: Color.orange.opacity(0.85)
        default: Palette.sage.opacity(0.5)
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
                Text(cm >= thresholdCm ? "保持这个距离" : "再坐远一点")
                    .font(.subheadline)
                    .foregroundStyle(cm >= thresholdCm ? Palette.gold : Color.orange)
            }
        case .ready(let cm):
            Text("\(cm) 厘米")
                .font(.title.weight(.medium))
                .foregroundStyle(Palette.gold)
        case .unavailable(let message):
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.foam)
                .padding(.horizontal)
        }
    }

    private func pass() {
        guard !didPass else { return }
        didPass = true
        checker.stop()
        onPass()
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
