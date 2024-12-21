import 'capture_platform_interface.dart';

import 'package:flutter/services.dart';

/// An implementation of [CapturePlatform] that uses method channels and event channels.
class EventChannelCapture extends CapturePlatform {
  final EventChannel eventChannel = const EventChannel('capture/events');

  Stream<List<double>> get audioStream {
    return eventChannel
        .receiveBroadcastStream()
        .map((event) => (event as List).map((e) => e as double).toList());
  }
}
