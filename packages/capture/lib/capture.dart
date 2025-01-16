import 'package:flutter/services.dart';
import 'dart:typed_data';

class Capture {
  static const MethodChannel _methodChannel = MethodChannel('capture/method');
  static const EventChannel _rawAudioEventChannel =
      EventChannel('capture/raw_audio_events');

  // Stream for raw audio data
  Stream<Uint8List> get rawAudioStream {
    return _rawAudioEventChannel
        .receiveBroadcastStream()
        .map((event) => event as Uint8List); // Now correctly expects Uint8List
  }

  // Start audio capture
  Future<void> startAudioCapture() async {
    await _methodChannel.invokeMethod('startAudioCapture');
  }

  // Stop audio capture
  Future<void> stopAudioCapture() async {
    await _methodChannel.invokeMethod('stopAudioCapture');
  }
}
