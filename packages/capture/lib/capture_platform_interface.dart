import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'capture_method_channel.dart';
import 'capture_event_channel.dart';

abstract class CapturePlatform extends PlatformInterface {
  /// Constructs a CapturePlatform.
  CapturePlatform() : super(token: _token);

  static final Object _token = Object();

  static CapturePlatform _instance = MethodChannelCapture();
  static EventChannelCapture _event = EventChannelCapture();

  /// The default instance of [CapturePlatform] to use.
  ///
  /// Defaults to [MethodChannelCapture].
  static CapturePlatform get instance => _instance;
  static EventChannelCapture get eventChannel => _event;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [CapturePlatform] when
  /// they register themselves.
  static set instance(CapturePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() async {
    return '1.0.0';
  }
}
