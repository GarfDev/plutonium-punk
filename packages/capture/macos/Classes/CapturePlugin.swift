//
//  CapturePlugin.swift
//  Your macOS Flutter Plugin
//

import AVFoundation
import Cocoa
import FlutterMacOS
import ScreenCaptureKit

/// Marked @available(macOS 12.3, *) because ScreenCaptureKit requires macOS 12.3+
@available(macOS 15.0, *)
public class CapturePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // MARK: - Properties

    private var rawAudioEventSink: FlutterEventSink?
    private var currentStream: SCStream?
    private var currentOutput: CaptureStreamOutput?

    /// Check if we can record. On macOS, we must have screen recording permissions granted.
    var canRecord: Bool {
        get async {
            do {
                NSLog("Checking screen recording permissions")
                // Checking for shareable content is how we see if the user has granted permission
                _ = try await SCShareableContent.excludingDesktopWindows(
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

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "capture/method",
            binaryMessenger: registrar.messenger)
        let eventChannel = FlutterEventChannel(
            name: "capture/raw_audio_events",
            binaryMessenger: registrar.messenger)

        let instance = CapturePlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - Flutter Method Calls

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startAudioCapture":
            Task {
                do {
                    // Check permission
                    let can = await canRecord
                    if !can {
                        result("Screen recording permissions not granted.")
                        return
                    }
                    // Present the content picker so user can select screen/window
                    try await setupContentPicker()
                    result("Picker presented")
                } catch {
                    result(
                        FlutterError(
                            code: "PICKER_FAILED",
                            message: "Failed to show content picker",
                            details: error.localizedDescription))
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

    // MARK: - EventChannel Stream Handler

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
        // ContentSharingPickerManager is your own class that manages the screen picker UI
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

        // The "dummy" stream to show the picker (you won't actually use this if user picks a different display/window)
        guard let firstDisplay = try? await SCShareableContent.current.displays.first else {
            print("No displays found to create dummy SCContentFilter.")
            return
        }

        let dummyConfig = SCStreamConfiguration()
        dummyConfig.capturesAudio = true
        let dummyFilter = SCContentFilter(
            display: firstDisplay,
            excludingApplications: [],
            exceptingWindows: [])
        let dummyStream = SCStream(
            filter: dummyFilter,
            configuration: dummyConfig,
            delegate: nil)

        await ContentSharingPickerManager.shared.setupPicker(stream: dummyStream)
        await ContentSharingPickerManager.shared.showPicker()
    }

    // MARK: - Start/Stop Capture

    private func startCapture(with filter: SCContentFilter, preCreatedStream: SCStream?) {
        let scStream: SCStream

        if let streamFromPicker = preCreatedStream {
            scStream = streamFromPicker
        } else {
            let config = SCStreamConfiguration()
            
            config.capturesAudio = true
            config.showsCursor = false

            // For stereo audio:
            config.sampleRate = 48000
            config.channelCount = 1
            config.excludesCurrentProcessAudio = true

            scStream = SCStream(filter: filter, configuration: config, delegate: nil)
        }

        let output = CaptureStreamOutput(plugin: self)
        
        currentOutput = output
        currentStream = scStream

        do {
            try scStream.addStreamOutput(
                output,
                type: .audio,
                sampleHandlerQueue: .global(qos: .userInitiated))

            Task {
                do {
                    try await scStream.startCapture()
                    print("Audio capture started.")
                } catch let captureError as NSError {
                    print("Failed to start capture: \(captureError.localizedDescription)")
                    rawAudioEventSink?(
                        FlutterError(
                            code: "CAPTURE_FAILED",
                            message: "Failed to start capture",
                            details: captureError.localizedDescription))
                }
            }
        } catch {
            print("Error adding output to SCStream: \(error.localizedDescription)")
        }
    }

    private func stopCapture() async {
        guard let scStream = currentStream else { return }
        try? await scStream.stopCapture()
        currentStream = nil
        currentOutput = nil

        await ContentSharingPickerManager.shared.deactivatePicker()
    }

    // MARK: - Sending Audio to Flutter
    internal func sendRawAudioData(_ data: Data) {
        guard let sink = rawAudioEventSink else {
            print("rawAudioEventSink is not set.")
            return
        }



        // Send the raw audio data as a Uint8List to Flutter
        sink(FlutterStandardTypedData(bytes: data))
    }

    

}

// MARK: - CaptureStreamOutput (SCStreamOutput)

@available(macOS 15.0, *)
private class CaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    private weak var plugin: CapturePlugin?

    init(plugin: CapturePlugin) {
        self.plugin = plugin
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("SCStream stopped with error: \(error.localizedDescription)")
    }
    
    // Creates an AVAudioPCMBuffer instance on which to perform an average and peak audio level calculation.
    private nonisolated func createPCMBuffer(for sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        // Validate CMSampleBuffer
        guard CMSampleBufferIsValid(sampleBuffer) else {
            print("Invalid CMSampleBuffer.")
            return nil
        }

        // Extract AudioBufferList safely
        var audioBufferListCopy: AudioBufferList?
        do {
            try sampleBuffer.withAudioBufferList { audioBufferList, _ in
                audioBufferListCopy = audioBufferList.unsafePointer.pointee
            }
        } catch {
            print("Error accessing AudioBufferList: \(error)")
            return nil
        }

        guard var audioBufferList = audioBufferListCopy else {
            print("Failed to retrieve AudioBufferList.")
            return nil
        }

        // Validate AudioBufferList properties
        let bufferCount = Int(audioBufferList.mNumberBuffers)
        if bufferCount <= 0 || bufferCount > 10 { // Limit to catch corruption
            print("Invalid buffer count: \(bufferCount).")
            return nil
        }
        print("AudioBufferList contains \(bufferCount) buffer(s).")

        // Retrieve and validate format description
        guard let absd = sampleBuffer.formatDescription?.audioStreamBasicDescription else {
            print("Invalid or missing format description.")
            return nil
        }

        print("Sample Rate: \(absd.mSampleRate), Channels: \(absd.mChannelsPerFrame)")

        guard bufferCount == Int(absd.mChannelsPerFrame) else {
            print("Mismatch: Number of buffers (\(bufferCount)) does not match channel count (\(absd.mChannelsPerFrame)).")
            return nil
        }

        // Create AVAudioFormat
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: absd.mSampleRate,
            channels: AVAudioChannelCount(absd.mChannelsPerFrame)
        ) else {
            print("Failed to create AVAudioFormat.")
            return nil
        }
        
        // Create AVAudioPCMBuffer
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: &audioBufferList) else {
            print("Failed to create AVAudioPCMBuffer.")
            return nil
        }
        
        let isPCM = pcmBuffer.format.commonFormat == .pcmFormatInt16
        print("Is 16-bit PCM format: \(isPCM)")
        print("What format it using: \(pcmBuffer.format.commonFormat)")


        return pcmBuffer
    }

    func convertTo16BitPCM(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatChannelData = buffer.floatChannelData else {
            print("Failed to get floatChannelData")
            return nil
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var pcmData = Data()
        
        for channel in 0..<channelCount {
            let channelData = floatChannelData[channel]
            for sampleIndex in 0..<frameLength {
                let floatSample = channelData[sampleIndex]
                // Scale float [-1.0, 1.0] to 16-bit integer range [-32768, 32767]
                let intSample = Int16(floatSample * Float(Int16.max))
                pcmData.append(contentsOf: withUnsafeBytes(of: intSample.littleEndian) { Data($0) })
            }
        }
        
        return pcmData
    }

    
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else { return }
                
        let pcmBuffer = createPCMBuffer(for: sampleBuffer)
        
        
    
        // The data is already 16-bit mono, so send it directly to Flutter
        guard let pcmBuffer else { return }
        
        if let convertedPCMData = convertTo16BitPCM(from: pcmBuffer) {
            plugin?.sendRawAudioData(convertedPCMData)
        }

    }

}
