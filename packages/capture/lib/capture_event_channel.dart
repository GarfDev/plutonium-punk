import 'capture_platform_interface.dart';

import 'package:flutter/services.dart';

/// An implementation of [CapturePlatform] that uses method channels and event channels.
class EventChannelCapture extends CapturePlatform {
  final EventChannel eventChannel = const EventChannel('capture/events');

  Stream<Uint8List> get audioStream {
    return eventChannel
        .receiveBroadcastStream()
        .map((event) => event as Uint8List);
  }
}
