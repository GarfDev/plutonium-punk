import Foundation
import ScreenCaptureKit
import AVFoundation

class SystemAudioCapture: NSObject, SCStreamDelegate, SCStreamOutput {
    // Make sure the closure property is typed
    var onAudioData: ((Data) -> Void)?
    
    private var stream: SCStream?
    private var audioQueue = DispatchQueue(label: "com.example.audio.processing")

    @MainActor
    func startCapture() async throws {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = shareableContent.displays.first else {
            throw NSError(domain: "SystemAudioCapture", code: -1, userInfo: [NSLocalizedDescriptionKey: "No display available"])
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)

        let audioConfig = SCAudioConfiguration()
        audioConfig.sampleRate = 48000
        audioConfig.channelCount = 2
        config.audioConfiguration = audioConfig

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try await newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        try await newStream.startCapture()

        self.stream = newStream
    }

    @MainActor
    func stopCapture() async {
        do {
            try await stream?.stopCapture()
        } catch {
            print("Failed to stop capture: \(error)")
        }
        stream = nil
    }

    // MARK: SCStreamDelegate
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error)")
    }

    // MARK: SCStreamOutput
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: nil, dataPointerOut: &dataPointer)

        if status == noErr, let dataPointer = dataPointer {
            let audioData = Data(bytes: dataPointer, count: length)
            onAudioData?(audioData)
        }
    }
}
