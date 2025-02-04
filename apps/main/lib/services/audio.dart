import 'dart:async';

import 'package:capture/capture.dart';
import 'package:flutter/foundation.dart';

class AudioService {
  final Capture _capture = Capture();
  final StreamController<List<int>> _audioController =
      StreamController.broadcast();

  bool _isCapturing = false;

  /// Public stream of audio samples (each element is a list of int16 samples).
  Stream<List<int>> get audioStream => _audioController.stream;

  AudioService();

  /// Start the audio capture from the microphone.
  Future<void> startCapture() async {
    if (_isCapturing) return;
    _isCapturing = true;

    await _capture.startAudioCapture();

    // Listen to raw bytes from the mic and convert to int16 samples
    _capture.rawAudioStream.listen((chunk) {
      _audioController.add(chunk);
    }, onError: (err) {
      debugPrint("AudioService - Audio Stream Error: $err");
    });

    debugPrint("AudioService - Capture started.");
  }

  /// Stop the audio capture.
  Future<void> stopCapture() async {
    if (!_isCapturing) return;
    _isCapturing = false;

    await _capture.stopAudioCapture();
    debugPrint("AudioService - Capture stopped.");
  }

  /// Cleanly dispose resources. Call this when you no longer need the service.
  Future<void> dispose() async {
    await _audioController.close();
  }
}
