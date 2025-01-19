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
            // The user picked something from the SCContentSharingPicker
            scStream = streamFromPicker
            print("Using pre-created stream from the picker.")
        } else {
            // If we didn't get a stream from the picker, create one ourselves
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.showsCursor = false
            config.excludesCurrentProcessAudio = true
                        

            
            scStream = SCStream(filter: filter, configuration: config, delegate: nil)
            print("Created new SCStream with config = \(config)")
        }

        let output = CaptureStreamOutput(plugin: self)
        currentOutput = output
        currentStream = scStream

        do {
            // Add audio output
            try scStream.addStreamOutput(
                output,
                type: .audio,
                sampleHandlerQueue: .global(qos: .userInitiated))
            // Start capturing
            Task {
                do {
                    try await scStream.startCapture()
                    print("Audio (and screen) capture started.")
                } catch let captureError as NSError {
                    print("Failed to start capture: \(captureError.localizedDescription)")
                    if let sink = rawAudioEventSink {
                        sink(FlutterError(code: "CAPTURE_FAILED", message: "Failed to start capture", details: captureError.localizedDescription))
                    }
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

    internal func sendRawAudioData(_ sampleBuffer: CMSampleBuffer) {
        guard let sink = rawAudioEventSink else {
            print("rawAudioEventSink is not set.")
            return
        }

        // Extract raw PCM data from CMSampleBuffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            print("Failed to get block buffer from CMSampleBuffer")
            return
        }

        let length = CMBlockBufferGetDataLength(blockBuffer)
        var audioData = Data(count: length)

        audioData.withUnsafeMutableBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
            }
        }

        // Send the raw PCM data to Flutter as a FlutterStandardTypedData object
        sink(FlutterStandardTypedData(bytes: audioData))
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

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else { return }

        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee {
            print("Audio Format Details:")
            print("- Sample Rate: \(asbd.mSampleRate)")
            print("- Channels: \(asbd.mChannelsPerFrame)")
            print("- Bits Per Sample: \(asbd.mBitsPerChannel)")
            print("- Format Flags: \(asbd.mFormatFlags)")
        }


        
        Task { @MainActor in
            // Send raw PCM data to Flutter
            plugin?.sendRawAudioData(sampleBuffer)
        }
    }


}
