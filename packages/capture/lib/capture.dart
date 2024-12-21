import 'package:flutter/services.dart';

class Capture {
  static const MethodChannel _methodChannel = MethodChannel('capture/method');
  static const EventChannel _eventChannel = EventChannel('capture/events');

  Stream<Uint8List> get audioStream {
    return _eventChannel
        .receiveBroadcastStream()
        .map((event) => event as Uint8List);
  }

  Stream<List<double>> get amplitudeStream {
    return _eventChannel
        .receiveBroadcastStream()
        .map((event) => (event as List).map((e) => e as double).toList());
  }

  Future<void> startAudioCapture() async {
    await _methodChannel.invokeMethod('startAudioCapture');
  }

  Future<void> stopAudioCapture() async {
    await _methodChannel.invokeMethod('stopAudioCapture');
  }
}
