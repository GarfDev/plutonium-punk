import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_recorder_platform_interface.dart';

/// An implementation of [AudioRecorderPlatform] that uses method channels.
class MethodChannelAudioRecorder extends AudioRecorderPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('audio_recorder');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
