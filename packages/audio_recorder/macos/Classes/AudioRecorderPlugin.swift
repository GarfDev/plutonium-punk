import Cocoa
import FlutterMacOS
import ScreenCaptureKit
import AVFoundation

@available(macOS 13.0, *)
public class AudioCapturePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var audioStream: SCStream?
    private var isRecording = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "audio_recorder", binaryMessenger: registrar.messenger)
        let eventChannel = FlutterEventChannel(name: "audio_recorder_stream", binaryMessenger: registrar.messenger)

        let instance = AudioCapturePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startRecording":
            let args = call.arguments as? [String:Any]
            let outputPath = args?["outputPath"] as? String
            startRecording(outputPath: outputPath, result: result)
        case "stopRecording":
            stopRecording(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startRecording(outputPath: String?, result: @escaping FlutterResult) {

        if isRecording {
            result(nil)
            return
        }

        isRecording = true

        SCShareableContent.getWithCompletionHandler { shareableContent, error in
            guard error == nil else {
                self.isRecording = false
                result(FlutterError(code: "CONTENT_ERROR", message: "Error getting shareable content: \(error!)", details: nil))
                return
            }

            guard let display = shareableContent?.displays.first else {
                self.isRecording = false
                result(FlutterError(code: "NO_DISPLAY", message: "No available displays", details: nil))
                return
            }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

            let config = SCStreamConfiguration()
            // Dummy resolution to start stream (not capturing video, but required)
            config.width = 1280
            config.height = 720
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.capturesAudio = true
            config.showsCursor = false


            do {
                let stream =  SCStream(filter: filter, configuration: config, delegate: nil)
                self.audioStream = stream

                let output = MyAudioStreamOutput { [weak self] audioData in
                    self?.eventSink?(audioData)
                    // Optional: write to file if outputPath is provided
                }

                let sampleQueue = DispatchQueue(label: "com.example.audio_capture")

                try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: sampleQueue)

                stream.startCapture { error in
                    if let error = error {
                        self.isRecording = false
                        result(FlutterError(code: "START_ERROR", message: "Failed to start capture: \(error)", details: nil))
                    } else {
                        result(nil)
                    }
                }
            } catch {
                self.isRecording = false
                result(FlutterError(code: "STREAM_ERROR", message: "Failed to create stream: \(error)", details: nil))
            }
        }
    }

    private func stopRecording(result: FlutterResult) {
        guard isRecording else {
            result(nil)
            return
        }

        self.audioStream?.stopCapture()
        self.isRecording = false
        self.audioStream = nil

    }

    // FlutterStreamHandler
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

@available(macOS 13.0, *)
class MyAudioStreamOutput: NSObject, SCStreamOutput {
    let audioCallback: ([UInt8]) -> Void

    init(audioCallback: @escaping ([UInt8]) -> Void) {
        self.audioCallback = audioCallback
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: nil, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer, length > 0 else { return }

        let bytePtr = UnsafeRawPointer(dataPointer).bindMemory(to: UInt8.self, capacity: length)
        let buffer = UnsafeBufferPointer<UInt8>(start: bytePtr, count: length)
        let data = Array(buffer)

        audioCallback(data)
    }
}
