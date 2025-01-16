import AVFoundation
import Cocoa
import FlutterMacOS
import ScreenCaptureKit

@available(macOS 15.0, *)
public class CapturePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // MARK: - Stored Properties

    private var rawAudioEventSink: FlutterEventSink?
    private var currentStream: SCStream?
    private var currentOutput: CaptureStreamOutput?

    var canRecord: Bool {
        get async {
            do {
                NSLog("Checking screen recording permissions")
                try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )
                NSLog("Screen recording permissions granted")
                return true
            } catch {
                NSLog("Screen recording permissions denied: %@", error.localizedDescription)
                return false
            }
        }
    }

    // MARK: - Plugin Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "capture/method",
            binaryMessenger: registrar.messenger
        )
        let rawAudioEventChannel = FlutterEventChannel(
            name: "capture/raw_audio_events",
            binaryMessenger: registrar.messenger
        )

        let instance = CapturePlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        rawAudioEventChannel.setStreamHandler(instance)
    }

    // MARK: - Flutter Method Channel Handler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startAudioCapture":
            Task {
                do {
                    let ableToRecord = await canRecord

                    if !ableToRecord {
                        result("Screen recording permissions not granted.")
                        return
                    }

                    try await setupContentPicker()
                    result("Picker presented")
                } catch {
                    result(
                        FlutterError(
                            code: "PICKER_FAILED",
                            message: "Failed to show content picker",
                            details: error.localizedDescription
                        )
                    )
                }
            }

        case "stopAudioCapture":
            Task {
                await stopCapture()
                result("Capture stopped")
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Flutter Event Channel Handlers

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        rawAudioEventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        rawAudioEventSink = nil
        Task {
            await stopCapture()
        }
        return nil
    }

    // MARK: - Content Picker Setup

    private func setupContentPicker() async throws {
        await ContentSharingPickerManager.shared.setContentSelectedCallback {
            [weak self] filter, pickedStream in
            guard let self = self else { return }
            self.startCapture(with: filter, preCreatedStream: pickedStream)
        }

        await ContentSharingPickerManager.shared.setContentSelectionCancelledCallback { _ in
            print("Picker was canceled, no capture started.")
        }

        await ContentSharingPickerManager.shared.setContentSelectionFailedCallback { error in
            print("Picker failed: \(error.localizedDescription)")
        }

        guard let firstDisplay = try? await SCShareableContent.current.displays.first else {
            print("No displays available for creating SCContentFilter")
            return
        }

        let dummyConfig = SCStreamConfiguration()
        dummyConfig.capturesAudio = true
        
        let dummyFilter = SCContentFilter(
            display: firstDisplay,
            excludingApplications: [],
            exceptingWindows: []
        )
        let dummyStream = SCStream(filter: dummyFilter, configuration: dummyConfig, delegate: nil)

        await ContentSharingPickerManager.shared.setupPicker(stream: dummyStream)
        await ContentSharingPickerManager.shared.showPicker()
    }

    // MARK: - Capture Control

    private func startCapture(with filter: SCContentFilter, preCreatedStream: SCStream?) {
        let scStream: SCStream
        if let streamFromPicker = preCreatedStream {
            print("Using pre-created stream for capture.")
            scStream = streamFromPicker
        } else {
            let config = SCStreamConfiguration()
            print("Created new stream for capture with config.", config)
            config.capturesAudio = true  // Enable audio capture

            // Optional: Set the desired sample rate (not explicitly configurable in SCStreamConfig)
            // By default, SCStream will use the system's native sample rate (e.g., 48 kHz).
            // Ensure Deepgram or downstream processors can handle this.

            scStream = SCStream(filter: filter, configuration: config, delegate: nil)
        }

        let output = CaptureStreamOutput(plugin: self)
        
        currentOutput = output
        currentStream = scStream

        do {
            try scStream.addStreamOutput(
                output,
                type: .audio,
                sampleHandlerQueue: .global(qos: .userInitiated)
            )

            Task {
                do {
                    try await scStream.startCapture()
                    print("Audio and screen capture started successfully.")
                } catch {
                    print("Failed to start SCStream capture: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Error adding stream output: \(error.localizedDescription)")
        }
    }

    private func stopCapture() async {
        guard let scStream = currentStream else { return }

        try? await scStream.stopCapture()

        currentStream = nil
        currentOutput = nil

        await ContentSharingPickerManager.shared.deactivatePicker()
    }

    // MARK: - Delivering Data to Flutter

    internal func sendRawAudioData(_ rawPCMData: Data) {
        guard let rawAudioEventSink = rawAudioEventSink else {
            print("Raw audio event sink is not available")
            return
        }
        rawAudioEventSink(FlutterStandardTypedData(bytes: rawPCMData))
    }
}

// MARK: - CaptureStreamOutput

@available(macOS 15.0, *)
private class CaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {

    private weak var plugin: CapturePlugin?

    init(plugin: CapturePlugin) {
        self.plugin = plugin
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Screen capture stream stopped: \(error.localizedDescription)")
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {

        if let rawPCMData = createRawPCMData(from: sampleBuffer) {
            Task { @MainActor in
                plugin?.sendRawAudioData(rawPCMData)
            }
        } else {
            print("Failed to create raw PCM data from sample buffer.")
        }
    }

    private func createRawPCMData(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let formatDesc = sampleBuffer.formatDescription,
            let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        else {
            return nil
        }

        // Dereference the pointer to get the AudioStreamBasicDescription structure
        let asbd = asbdPointer.pointee

        // Extract raw audio data from the sample buffer
        guard let blockBuffer = sampleBuffer.dataBuffer else { return nil }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let pointer = dataPointer else {
            return nil
        }

        let rawData = Data(bytes: pointer, count: totalLength)

        // If needed, convert audio format (e.g., resample to 16 kHz and convert to 16-bit)
        if Int(asbd.mSampleRate) != 16000 || asbd.mBitsPerChannel != 16 {
            return convertAudioFormat(rawData, from: asbd, targetSampleRate: 16000)
        }

        return rawData
    }

    private func convertAudioFormat(
        _ rawData: Data,
        from sourceASBD: AudioStreamBasicDescription,
        targetSampleRate: Float64
    ) -> Data? {
        // Make a mutable copy of sourceASBD since it is passed as inout
        var mutableASBD = sourceASBD

        // Create input audio format
        guard let sourceFormat = AVAudioFormat(streamDescription: &mutableASBD) else {
            print("Failed to create source audio format.")
            return nil
        }

        // Create target audio format
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,  // Mono
            interleaved: true
        )

        guard let targetFormat = targetFormat else {
            print("Failed to create target audio format.")
            return nil
        }

        // Initialize AVAudioConverter
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            print("Failed to initialize audio converter.")
            return nil
        }

        // Prepare buffers for conversion
        let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(rawData.count) / sourceASBD.mBytesPerFrame
        )
        inputBuffer?.frameLength = inputBuffer?.frameCapacity ?? 0

        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(targetSampleRate)
        )

        do {
            let _ = try converter.convert(to: outputBuffer!, error: nil) {
                _, outStatus -> AVAudioBuffer? in
                outStatus.pointee = .haveData
                return inputBuffer
            }

            guard let outputData = outputBuffer?.int16ChannelData else { return nil }
            return Data(bytes: outputData, count: Int(outputBuffer!.frameLength) * 2)  // 16-bit audio
        } catch {
            print("Audio conversion error: \(error.localizedDescription)")
            return nil
        }
    }

}
