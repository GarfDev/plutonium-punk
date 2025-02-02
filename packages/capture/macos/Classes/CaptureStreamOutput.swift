//
//  CaptureStreamOutput.swift
//  Your macOS Flutter Plugin
//

import AVFoundation
import ScreenCaptureKit

@available(macOS 15.0, *)
class CaptureStreamOutput: NSObject, SCStreamOutput {
    private weak var plugin: CapturePlugin?

    init(plugin: CapturePlugin) {
        self.plugin = plugin
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("SCStream stopped with error: \(error.localizedDescription)")
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else { return }

        let pcmBuffer = createPCMBuffer(from: sampleBuffer)

        guard let pcmBuffer else { return }

        if let convertedPCMData = convertTo16BitPCM(from: pcmBuffer) {
            plugin?.sendRawAudioData(convertedPCMData)
        }

    }

    // MARK: - PCM Buffer Utilities

    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard CMSampleBufferIsValid(sampleBuffer),
            let formatDescription = sampleBuffer.formatDescription,
            let absd = formatDescription.audioStreamBasicDescription
        else {
            NSLog("Invalid CMSampleBuffer or missing format description.")
            return nil
        }

        var audioBufferListCopy: AudioBufferList?
        do {
            try sampleBuffer.withAudioBufferList { audioBufferList, _ in
                audioBufferListCopy = audioBufferList.unsafePointer.pointee
            }
        } catch {
            NSLog("Error accessing AudioBufferList: \(error.localizedDescription)")
            return nil
        }

        guard
            let format = AVAudioFormat(
                standardFormatWithSampleRate: absd.mSampleRate,
                channels: AVAudioChannelCount(absd.mChannelsPerFrame)
            )
        else {
            NSLog("Failed to create AVAudioFormat.")
            return nil
        }

        return AVAudioPCMBuffer(
            pcmFormat: format,
            bufferListNoCopy: &audioBufferListCopy!
        )
    }

    private func convertTo16BitPCM(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatChannelData = buffer.floatChannelData else {
            NSLog("Failed to get floatChannelData.")
            return nil
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var pcmData = Data(capacity: frameLength * channelCount * MemoryLayout<Int16>.size)

        for channel in 0..<channelCount {
            let channelData = floatChannelData[channel]
            for sampleIndex in 0..<frameLength {
                let intSample = Int16(
                    max(-1.0, min(1.0, channelData[sampleIndex])) * Float(Int16.max)
                )
                pcmData.append(contentsOf: withUnsafeBytes(of: intSample.littleEndian) { Data($0) })
            }
        }

        return pcmData
    }
}
