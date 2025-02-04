//
//  CapturePlugin.swift
//  Your macOS Flutter Plugin
//

import AVFoundation
import Cocoa
import FlutterMacOS
import ScreenCaptureKit

@available(macOS 15.0, *)
public class CapturePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // MARK: - Properties
    private var audioDataBuffer = Data()
    private let bufferSizeThreshold = 1024 * 16  // Example threshold size

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
            config.captureMicrophone = true

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
    func sendRawAudioData(_ data: Data) {
        guard let sink = rawAudioEventSink else { return }
        audioDataBuffer.append(data)

        if audioDataBuffer.count >= bufferSizeThreshold {
            sink(FlutterStandardTypedData(bytes: audioDataBuffer))
            audioDataBuffer.removeAll(keepingCapacity: true)
        }
    }

}
