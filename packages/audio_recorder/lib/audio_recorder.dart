import 'dart:async';
import 'dart:ffi'; // if needed for any FFI approach
import 'package:flutter/services.dart';

class AudioRecorder {
  static const MethodChannel _channel = MethodChannel('audio_recorder');
  static const EventChannel _audioEventChannel =
      EventChannel('audio_recorder_stream');

  static Stream<List<int>>? _audioStream;

  /// Start capturing system audio.
  /// Optionally specify output file path or just stream the data.
  static Future<void> startRecording({String? outputPath}) async {
    await _channel.invokeMethod('startRecording', {
      'outputPath': outputPath,
    });
  }

  /// Stop capturing system audio.
  static Future<void> stopRecording() async {
    await _channel.invokeMethod('stopRecording');
  }

  /// Returns a stream of raw PCM audio frames.
  static Stream<List<int>> get audioStream {
    _audioStream ??= _audioEventChannel.receiveBroadcastStream().map((data) {
      // Data will come as Uint8List or List<int> from Swift.
      return List<int>.from(data);
    });
    return _audioStream!;
  }
}
