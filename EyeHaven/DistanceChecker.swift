import ARKit
import AVFoundation
import Observation
import Vision

enum DistanceStatus: Equatable {
    case starting
    case noFace
    case reading(cm: Int)
    case ready(cm: Int)
    case unavailable(String)
}

@Observable
@MainActor
final class DistanceChecker: NSObject {
    var status: DistanceStatus = .starting
    let previewLayer = AVCaptureVideoPreviewLayer()
    private(set) var arSession: ARSession?

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "eyehaven.distance.camera")
    private var usesARFace = false
    private var thresholdCm = 40.0
    private var passingStreak = 0
    private var isRunning = false
    private weak var captureDevice: AVCaptureDevice?

    func start(thresholdCm: Int) {
        self.thresholdCm = Double(thresholdCm)
        passingStreak = 0
        status = .starting
        isRunning = true

        requestCamera { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.status = .unavailable("请在系统设置里允许 EyeHaven 使用摄像头。")
                return
            }
            if ARFaceTrackingConfiguration.isSupported {
                self.usesARFace = true
                self.startARFace()
            } else {
                self.usesARFace = false
                self.configureVisionSession()
            }
        }
    }

    private func requestCamera(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }

    func stop() {
        isRunning = false
        arSession?.pause()
        arSession = nil
        sessionQueue.async { [captureSession] in
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    private func startARFace() {
        let session = ARSession()
        session.delegate = self
        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        arSession = session
    }

    private func configureVisionSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .medium

            self.captureSession.inputs.forEach { self.captureSession.removeInput($0) }
            self.captureSession.outputs.forEach { self.captureSession.removeOutput($0) }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: device)
            else {
                Task { @MainActor in
                    self.status = .unavailable("找不到前置摄像头。")
                }
                self.captureSession.commitConfiguration()
                return
            }

            if self.captureSession.canAddInput(input) {
                self.captureSession.addInput(input)
            }
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }
            self.videoOutput.connection(with: .video)?.isEnabled = true
            self.captureSession.commitConfiguration()

            Task { @MainActor in
                self.captureDevice = device
                self.previewLayer.session = self.captureSession
                self.previewLayer.videoGravity = .resizeAspectFill
            }

            self.captureSession.startRunning()
        }
    }

    private func consider(distanceCm: Double, hasFace: Bool) {
        guard isRunning else { return }
        guard hasFace, distanceCm.isFinite, distanceCm > 8, distanceCm < 200 else {
            passingStreak = 0
            status = .noFace
            return
        }

        let cm = Int(distanceCm.rounded())
        if distanceCm + 1 >= thresholdCm {
            passingStreak += 1
            if passingStreak >= 6 {
                status = .ready(cm: cm)
            } else {
                status = .reading(cm: cm)
            }
        } else {
            passingStreak = 0
            status = .reading(cm: cm)
        }
    }
}

extension DistanceChecker: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        let face = anchors.compactMap { $0 as? ARFaceAnchor }.first
        let cm: Double?
        if let face {
            let t = face.transform.columns.3
            cm = Double(sqrt(t.x * t.x + t.y * t.y + t.z * t.z) * 100)
        } else {
            cm = nil
        }
        Task { @MainActor in
            if let cm {
                self.consider(distanceCm: cm, hasFace: true)
            } else {
                self.consider(distanceCm: 0, hasFace: false)
            }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.status = .unavailable(error.localizedDescription)
        }
    }
}

extension DistanceChecker: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
        try? handler.perform([request])
        let face = request.results?.first

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        Task { @MainActor in
            guard let face else {
                self.consider(distanceCm: 0, hasFace: false)
                return
            }
            let fovDegrees = Double(self.captureDevice?.activeFormat.videoFieldOfView ?? 60)
            let cm = Self.estimateCentimeters(
                faceWidth: face.boundingBox.width,
                imageWidth: width,
                imageHeight: height,
                verticalFOVDegrees: fovDegrees
            )
            self.consider(distanceCm: cm, hasFace: true)
        }
    }

    /// Assumes a child's face is about 13 cm wide. This is an estimate, not a medical measurement.
    nonisolated static func estimateCentimeters(
        faceWidth: CGFloat,
        imageWidth: Int,
        imageHeight: Int,
        verticalFOVDegrees: Double
    ) -> Double {
        let vfov = verticalFOVDegrees * .pi / 180
        let aspect = Double(max(imageWidth, 1)) / Double(max(imageHeight, 1))
        let hfov = 2 * atan(tan(vfov / 2) * aspect)
        let faceRadians = hfov * Double(faceWidth)
        let half = max(faceRadians / 2, 0.01)
        let faceWidthMeters = 0.13
        return (faceWidthMeters / 2) / tan(half) * 100
    }
}
