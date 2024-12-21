import 'package:flutter/services.dart';

class Capture {
  static const MethodChannel _methodChannel =
      MethodChannel('audio_capture/method');
  static const EventChannel _eventChannel =
      EventChannel('audio_capture/events');

  Stream<Uint8List> get audioStream {
    return _eventChannel
        .receiveBroadcastStream()
        .map((event) => event as Uint8List);
  }

  Future<void> startAudioCapture() async {
    await _methodChannel.invokeMethod('startAudioCapture');
  }

  Future<void> stopAudioCapture() async {
    await _methodChannel.invokeMethod('stopAudioCapture');
  }
}
