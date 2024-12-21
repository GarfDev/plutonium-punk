import 'package:flutter/services.dart';

import 'capture_platform_interface.dart';

/// An implementation of [CapturePlatform] that uses method channels.
class MethodChannelCapture extends CapturePlatform {
  /// The method channel used to interact with the native platform.
  final platform = const MethodChannel('capture');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await platform.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  Future<void> startAudioCapture() async {
    await platform.invokeMethod('startAudioCapture');
  }

  Future<void> stopAudioCapture() async {
    await platform.invokeMethod('stopAudioCapture');
  }
}
