import AVFoundation
import AudioToolbox
import Cocoa
import FlutterMacOS

public class CapturePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    final var eventSink: FlutterEventSink?
    private var audioQueue: AudioQueueRef?

    // MARK: - Plugin Registration
    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "capture/method", binaryMessenger: registrar.messenger)
        let eventChannel = FlutterEventChannel(
            name: "capture/events", binaryMessenger: registrar.messenger)
        let instance = CapturePlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - MethodChannel Handler
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startAudioCapture":
            startAudioCapture()
            result("Audio capture started")
        case "stopAudioCapture":
            stopAudioCapture()
            result("Audio capture stopped")
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - EventChannel Stream Handler
    public func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        stopAudioCapture()
        return nil
    }

    // MARK: - Audio Capture
    private func startAudioCapture() {
        var audioFormat = AudioStreamBasicDescription(
            mSampleRate: 44100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        // Pass `self` as user data
        AudioQueueNewInput(
            &audioFormat,
            audioQueueCallback,  // Use global callback
            Unmanaged.passUnretained(self).toOpaque(),  // Pass `self` context
            nil,
            nil,
            0,
            &audioQueue
        )

        guard let queue = audioQueue else {
            print("Failed to create audio queue")
            return
        }

        for _ in 0..<3 {
            var buffer: AudioQueueBufferRef?
            AudioQueueAllocateBuffer(queue, 44100, &buffer)
            if let buffer = buffer {
                AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
            }
        }

        AudioQueueStart(queue, nil)
    }

    private func stopAudioCapture() {
        guard let queue = audioQueue else { return }
        AudioQueueStop(queue, true)
        AudioQueueDispose(queue, true)
        audioQueue = nil
    }
}

// MARK: - Global Callback Function
func audioQueueCallback(
    inUserData: UnsafeMutableRawPointer?,
    inAQ: AudioQueueRef,
    inBuffer: AudioQueueBufferRef,
    inStartTime: UnsafePointer<AudioTimeStamp>,
    inNumPackets: UInt32,
    inPacketDesc: UnsafePointer<AudioStreamPacketDescription>?
) {
    guard let userData = inUserData else { return }
    let plugin = Unmanaged<CapturePlugin>.fromOpaque(userData).takeUnretainedValue()

    if let eventSink = plugin.eventSink {
        // Convert raw audio data to Int16 samples
        let bufferPointer = inBuffer.pointee.mAudioData.bindMemory(
            to: Int16.self, capacity: Int(inBuffer.pointee.mAudioDataByteSize) / 2)
        let buffer = UnsafeBufferPointer(
            start: bufferPointer, count: Int(inBuffer.pointee.mAudioDataByteSize) / 2)

        // Map amplitudes to a normalized range (e.g., -1.0 to 1.0)
        let amplitudes = buffer.map { NSNumber(value: Float($0) / Float(Int16.max)) }

        // Send the normalized amplitudes to Flutter
        plugin.eventSink?(amplitudes)

    }

    // Re-enqueue the input buffer
    AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
}
