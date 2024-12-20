import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'audio_recorder_method_channel.dart';

abstract class AudioRecorderPlatform extends PlatformInterface {
  /// Constructs a AudioRecorderPlatform.
  AudioRecorderPlatform() : super(token: _token);

  static final Object _token = Object();

  static AudioRecorderPlatform _instance = MethodChannelAudioRecorder();

  /// The default instance of [AudioRecorderPlatform] to use.
  ///
  /// Defaults to [MethodChannelAudioRecorder].
  static AudioRecorderPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AudioRecorderPlatform] when
  /// they register themselves.
  static set instance(AudioRecorderPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
