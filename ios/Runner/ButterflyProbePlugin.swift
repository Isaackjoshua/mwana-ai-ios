import Flutter
import UIKit
import ButterflyImagingKit

class ButterflyProbePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private let imaging = ButterflyImaging.shared
    private var eventSink: FlutterEventSink?
    private var latestFrame: UIImage?
    private var isImaging = false
    private var availablePresets: [ImagingPreset] = []
    private var latestDepth: Double = 7.0
    private var latestDepthMin: Double = 2.0
    private var latestDepthMax: Double = 15.0
    private var latestGain: Int = 50

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.mwana_ai/butterfly_probe",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "com.mwana_ai/butterfly_probe_events",
            binaryMessenger: registrar.messenger()
        )
        let instance = ButterflyProbePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        case "initialize":
            Task { [weak self] in await self?.initializeSDK(result: result) }

        case "startImaging":
            let presetName = (call.arguments as? [String: Any])?["preset"] as? String
            Task { [weak self] in await self?.startImaging(presetName: presetName, result: result) }

        case "captureFrame":
            captureFrame(result: result)

        case "stopImaging":
            imaging.stopImaging()
            isImaging = false
            result(nil)

        case "setDepth":
            if let cm = (call.arguments as? [String: Any])?["cm"] as? Double {
                imaging.setDepth(Measurement(value: cm, unit: UnitLength.centimeters))
            }
            result(nil)

        case "setGain":
            if let gain = (call.arguments as? [String: Any])?["gain"] as? Int {
                imaging.setGain(gain)
            }
            result(nil)

        case "getAvailablePresets":
            result(availablePresets.map { $0.name })

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func initializeSDK(result: @escaping FlutterResult) async {
        guard let clientKey = Bundle.main.infoDictionary?["ButterflyClientKey"] as? String,
              !clientKey.isEmpty,
              clientKey != "YOUR_CLIENT_KEY_HERE" else {
            await MainActor.run {
                result(FlutterError(
                    code: "NO_KEY",
                    message: "ButterflyClientKey is not set. Add your client key to ios/Runner/ButterflyConfig.xcconfig.",
                    details: nil
                ))
            }
            return
        }

        do {
            try await imaging.startup(clientKey: clientKey)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.imaging.states = { [weak self] state, changes in
                    DispatchQueue.main.async { [weak self] in
                        self?.handleState(state, changes: changes)
                    }
                }
                result(nil)
            }
        } catch {
            await MainActor.run {
                result(FlutterError(
                    code: "INIT_FAILED",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        }
    }

    private func handleState(_ state: ImagingState, changes: ImagingStateChanges) {
        availablePresets = state.availablePresets
        latestGain = state.gain
        latestDepth = state.depth.converted(to: .centimeters).value
        latestDepthMin = state.depthBounds.lowerBound.converted(to: .centimeters).value
        latestDepthMax = state.depthBounds.upperBound.converted(to: .centimeters).value

        let probeStateStr: String
        switch state.probe.state {
        case .disconnected:
            probeStateStr = "disconnected"
            if isImaging {
                isImaging = false
                latestFrame = nil
            }
        case .firmwareIncompatible:
            probeStateStr = "firmwareIncompatible"
        case .hardwareIncompatible:
            probeStateStr = "hardwareIncompatible"
        @unknown default:
            probeStateStr = isImaging ? "imaging" : "connected"
        }

        emitEvent([
            "type": "state",
            "state": probeStateStr,
            "depthCm": latestDepth,
            "depthMin": latestDepthMin,
            "depthMax": latestDepthMax,
            "gain": latestGain,
        ])

        if isImaging && changes.bModeImageChanged, let image = state.bModeImage?.image {
            latestFrame = image
            if let previewData = downsampleJpeg(image, maxDimension: 320) {
                emitEvent(["type": "frame", "data": previewData.base64EncodedString()])
            }
        }
    }

    private func startImaging(presetName: String?, result: @escaping FlutterResult) async {
        let preset: ImagingPreset?
        if let name = presetName, !name.isEmpty {
            preset = availablePresets.first { $0.name.lowercased().contains(name.lowercased()) }
                ?? availablePresets.first
        } else {
            preset = availablePresets.first
        }

        do {
            try await imaging.startImaging(preset: preset, parameters: nil)
            isImaging = true
            await MainActor.run { result(nil) }
        } catch {
            await MainActor.run {
                result(FlutterError(
                    code: "IMAGING_FAILED",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        }
    }

    private func captureFrame(result: @escaping FlutterResult) {
        guard let image = latestFrame,
              let data = image.jpegData(compressionQuality: 0.95) else {
            result(FlutterError(code: "NO_FRAME", message: "No frame available yet", details: nil))
            return
        }
        result(FlutterStandardTypedData(bytes: data))
    }

    private func downsampleJpeg(_ image: UIImage, maxDimension: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.7)
    }

    private func emitEvent(_ event: [String: Any]) {
        eventSink?(event)
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
