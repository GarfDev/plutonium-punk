import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'dart:io';

class Capture {
  static const MethodChannel _methodChannel = MethodChannel('capture/method');
  static const EventChannel _rawAudioEventChannel =
      EventChannel('capture/raw_audio_events');

  // Stream for raw PCM audio data
  Stream<Uint8List> get rawAudioStream =>
      _rawAudioEventChannel.receiveBroadcastStream().map((event) {
        if (event is Uint8List) {
          return event;
        } else {
          throw FormatException("Invalid audio data received");
        }
      });

  /// Start audio capture
  Future<void> startAudioCapture() async {
    try {
      await _methodChannel.invokeMethod('startAudioCapture');
    } on PlatformException catch (e) {
      print("Failed to start audio capture: ${e.message}");
      rethrow;
    }
  }

  /// Stop audio capture
  Future<void> stopAudioCapture() async {
    try {
      await _methodChannel.invokeMethod('stopAudioCapture');
    } on PlatformException catch (e) {
      print("Failed to stop audio capture: ${e.message}");
      rethrow;
    }
  }

  /// Build a 44-byte WAV header for raw PCM data
  Uint8List buildWavHeader({
    required int totalAudioSamples,
    int sampleRate = 48000,
    int bitsPerSample = 32,
    int channels = 2,
  }) {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;

    // Total data size
    final dataSize = totalAudioSamples * channels * (bitsPerSample ~/ 8);
    final fileSize = 44 - 8 + dataSize;

    final buffer = BytesBuilder();

    // RIFF header
    buffer.add(asciiStringBytes('RIFF')); // ChunkID
    buffer.add(_intToBytes(fileSize, 4)); // ChunkSize
    buffer.add(asciiStringBytes('WAVE')); // Format

    // fmt sub-chunk
    buffer.add(asciiStringBytes('fmt ')); // Subchunk1ID
    buffer.add(_intToBytes(16, 4)); // Subchunk1Size (16 for PCM)
    buffer.add(_intToBytes(3, 2)); // AudioFormat (3 = Float)
    buffer.add(_intToBytes(channels, 2)); // NumChannels
    buffer.add(_intToBytes(sampleRate, 4)); // SampleRate
    buffer.add(_intToBytes(byteRate, 4)); // ByteRate
    buffer.add(_intToBytes(blockAlign, 2)); // BlockAlign
    buffer.add(_intToBytes(bitsPerSample, 2)); // BitsPerSample

    // data sub-chunk
    buffer.add(asciiStringBytes('data')); // Subchunk2ID
    buffer.add(_intToBytes(dataSize, 4)); // Subchunk2Size

    return buffer.toBytes();
  }

  /// Convert an integer to little-endian bytes
  Uint8List _intToBytes(int value, int length) {
    final result = ByteData(length);
    switch (length) {
      case 2:
        result.setInt16(0, value, Endian.little);
        break;
      case 4:
        result.setInt32(0, value, Endian.little);
        break;
    }
    return result.buffer.asUint8List();
  }

  /// Convert ASCII string to Uint8List
  Uint8List asciiStringBytes(String s) => Uint8List.fromList(s.codeUnits);

  /// Save raw PCM data to a WAV file
  Future<void> saveRawPCMToWav(Uint8List pcmData, String filePath,
      {int sampleRate = 48000,
      int bitsPerSample = 32,
      int channels = 2}) async {
    final totalAudioSamples =
        pcmData.length ~/ (channels * (bitsPerSample ~/ 8));
    final wavHeader = buildWavHeader(
      totalAudioSamples: totalAudioSamples,
      sampleRate: sampleRate,
      bitsPerSample: bitsPerSample,
      channels: channels,
    );

    final wavFile = Uint8List.fromList(wavHeader + pcmData);
    final file = File(filePath);
    await file.writeAsBytes(wavFile);
    print("Saved WAV file to $filePath");
  }
}
