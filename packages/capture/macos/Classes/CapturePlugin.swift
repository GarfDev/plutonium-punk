//
//  CapturePlugin.swift
//  Demonstrates integrating ScreenCaptureKit + ContentSharingPickerManager in a Flutter plugin.
//
//  Requirements:
//   - macOS 12.3 or later for ScreenCaptureKit.
//   - macOS 15.0 or concurrency back-deployment for async/await features.
//
//  Make sure your Xcode build settings support Swift concurrency appropriately.
//
import AVFoundation
import Cocoa
import FlutterMacOS
import ScreenCaptureKit

/// The main plugin class responsible for registering with Flutter and handling capture functionality.
@available(macOS 15.0, *)
public class CapturePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // MARK: - Stored Properties

    private var eventSink: FlutterEventSink?
    private var currentStream: SCStream?
    private var currentOutput: CaptureStreamOutput?

    var canRecord: Bool {
        get async {
            do {
                NSLog("Checking screen recording permissions")
                try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true)
                NSLog("Screen recording permissions granted")
                return true
            } catch {
                NSLog("Screen recording permissions denied: %@", error.localizedDescription)
                return false
            }
        }
    }

    // MARK: - Plugin Registration

    /// Registers the plugin with the Flutter engine. Called by the Flutter system.
    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "capture/method",
            binaryMessenger: registrar.messenger
        )
        let eventChannel = FlutterEventChannel(
            name: "capture/events",
            binaryMessenger: registrar.messenger
        )

        let instance = CapturePlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - Flutter Method Channel Handler

    /// Handles incoming method calls from the Flutter method channel.
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startAudioCapture":
            // Show the SCContentSharingPicker so the user can pick which content to capture.

      

            Task {
                do {
                    let ableToRecord = await canRecord
                    
                    if !ableToRecord {
                        result("... Not allowed")
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
            // Stop the ongoing capture session.
            Task {
                await stopCapture()
                result("Capture stopped")
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Flutter Event Channel (Stream) Handler

    /// Called when a Flutter stream starts listening for events.
    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    /// Called when a Flutter stream stops listening for events.
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        Task {
            await stopCapture()
        }
        return nil
    }

    // MARK: - Content Picker Setup

    /// Prepares the callbacks for content selection and shows the content picker UI.
    private func setupContentPicker() async throws {
        // 1. Define what happens when content is successfully selected.
        await ContentSharingPickerManager.shared.setContentSelectedCallback {
            [weak self] filter, pickedStream in
            guard let self = self else { return }
            // The user finished picking content. Start capturing immediately.
            self.startCapture(with: filter, preCreatedStream: pickedStream)
        }

        // 2. Define what happens if the user cancels the picker.
        await ContentSharingPickerManager.shared.setContentSelectionCancelledCallback {
            _ in
            print("Picker was canceled, no capture started.")
            // Optionally handle cancellation (e.g., self?.stopCapture()).
        }

        // 3. Define what happens if the picker fails.
        await ContentSharingPickerManager.shared.setContentSelectionFailedCallback {
            error in
            print("Picker failed: \(error.localizedDescription)")
            // Optionally handle or forward to Flutter as an error event.
        }

        // 4. Find the first available display (required to create the initial SCContentFilter).
        guard let firstDisplay = try? await SCShareableContent.current.displays.first else {
            print("No displays available for creating SCContentFilter")
            return
        }

        // Create a minimal SCStream so that the picker can reference it.
        let dummyConfig = SCStreamConfiguration()
        let dummyFilter = SCContentFilter(
            display: firstDisplay,
            excludingApplications: [],
            exceptingWindows: []
        )
        let dummyStream = SCStream(filter: dummyFilter, configuration: dummyConfig, delegate: nil)

        // 5. Pass this minimal stream to the manager, then show the picker.
        await ContentSharingPickerManager.shared.setupPicker(stream: dummyStream)
        await ContentSharingPickerManager.shared.showPicker()
    }

    // MARK: - Capture Control

    /// Starts capturing audio from the selected content filter and optional pre-created stream.
    private func startCapture(with filter: SCContentFilter, preCreatedStream: SCStream?) {
        // Use the provided SCStream if available, otherwise create a new one.
        let scStream: SCStream
        if let streamFromPicker = preCreatedStream {
            scStream = streamFromPicker
            // Optionally update delegate or other settings if needed.
        } else {
            // Create a new SCStream from the chosen filter.
            let config = SCStreamConfiguration()
            config.capturesAudio = true  // Key for capturing audio
            scStream = SCStream(filter: filter, configuration: config, delegate: nil)
        }

        // Create (or reuse) an output object to process sample buffers.
        let output = CaptureStreamOutput(plugin: self)
        currentOutput = output
        currentStream = scStream

        do {
            // Add audio output to the stream.
            try scStream.addStreamOutput(
                output,
                type: .audio,
                sampleHandlerQueue: .global(qos: .userInitiated)
            )

            // Start capturing asynchronously.
            Task {
                do {
                    try await scStream.startCapture()
                } catch {
                    print("Failed to start SCStream capture: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Error adding stream output: \(error.localizedDescription)")
        }
    }

    /// Stops any ongoing capture session.
    private func stopCapture() async {
        guard let scStream = currentStream else { return }

        // Stop the capture if active.
        try? await scStream.stopCapture()

        // Clean up references.
        currentStream = nil
        currentOutput = nil

        // Deactivate picker if needed.
        await ContentSharingPickerManager.shared.deactivatePicker()
    }

    // MARK: - Delivering Audio to Flutter

    /// Sends computed audio amplitudes to Flutter via the Event Channel.
    internal func sendAudioAmplitudes(_ amplitudes: [Float]) {
        guard let eventSink = eventSink else { return }
        let asNSNumberArray = amplitudes.map { NSNumber(value: $0) }
        eventSink(asNSNumberArray)
    }
}

// MARK: - CaptureStreamOutput

/// A helper class implementing SCStreamOutput for audio sample buffer processing.
@available(macOS 15.0, *)
private class CaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {

    private weak var plugin: CapturePlugin?

    init(plugin: CapturePlugin) {
        self.plugin = plugin
    }

    /// Called if the SCStream stops or encounters an error.
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Screen capture stream stopped: \(error.localizedDescription)")
    }

    /// Called for each sample buffer delivered (video or audio). We only process audio.
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard
            outputType == .audio,
            sampleBuffer.isValid
        else {
            return
        }

        // Convert the sample buffer to amplitude floats, then send to the plugin.
        if let amplitudes = self.createFloatAmplitudes(from: sampleBuffer) {
            Task { @MainActor in
                plugin?.sendAudioAmplitudes(amplitudes)
            }
        }
    }

    /// Converts the CMSampleBuffer to an array of normalized floats ([-1 ... 1]).
    private func createFloatAmplitudes(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard
            let formatDesc = sampleBuffer.formatDescription,
            let asbd = formatDesc.audioStreamBasicDescription
        else {
            return nil
        }

        // Construct an AVAudioFormat for Float32.
        guard
            let avFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(asbd.mSampleRate),
                channels: asbd.mChannelsPerFrame,
                interleaved: false
            )
        else {
            return nil
        }

        // Build an AVAudioPCMBuffer from the sample buffer.
        guard
            let pcmBuffer = try? AVAudioPCMBuffer.create(from: sampleBuffer, format: avFormat),
            let channelData = pcmBuffer.floatChannelData?[0]
        else {
            return nil
        }

        // Copy data from channel 0 into a Swift array.
        let frameCount = Int(pcmBuffer.frameLength)
        var amplitudes = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            amplitudes[i] = channelData[i]
        }

        return amplitudes
    }
}

// MARK: - AVAudioPCMBuffer Utility

/// Extension on AVAudioPCMBuffer to build an AVAudioPCMBuffer from a CMSampleBuffer.
@available(macOS 15.0, *)
extension AVAudioPCMBuffer {

    /// Creates a float-based AVAudioPCMBuffer from a CMSampleBuffer and an AVAudioFormat.
    static func create(
        from sampleBuffer: CMSampleBuffer,
        format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer? {

        // Get the CMBlockBuffer from the sample buffer.
        guard let blockBuffer = sampleBuffer.dataBuffer else { return nil }

        // Number of audio samples in this buffer.
        let numSamples = CMItemCount(CMSampleBufferGetNumSamples(sampleBuffer))

        // Create an AVAudioPCMBuffer with capacity for the audio data.
        guard
            let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(numSamples)
            )
        else {
            return nil
        }

        pcmBuffer.frameLength = pcmBuffer.frameCapacity

        let audioBufferList = pcmBuffer.mutableAudioBufferList
        var totalDataLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        // Acquire a pointer to the raw audio data in the CMBlockBuffer.
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalDataLength,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr,
            let destination = audioBufferList.pointee.mBuffers.mData
        else {
            return nil
        }

        // Copy the audio data from the CMBlockBuffer into the PCM buffer's memory.
        memcpy(destination, dataPointer, totalDataLength)

        return pcmBuffer
    }
}
