import 'package:flutter_test/flutter_test.dart';
import 'package:capture/capture.dart';
import 'package:capture/capture_platform_interface.dart';
import 'package:capture/capture_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockCapturePlatform
    with MockPlatformInterfaceMixin
    implements CapturePlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final CapturePlatform initialPlatform = CapturePlatform.instance;

  test('$MethodChannelCapture is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelCapture>());
  });

  test('getPlatformVersion', () async {
    Capture capturePlugin = Capture();
    MockCapturePlatform fakePlatform = MockCapturePlatform();
    CapturePlatform.instance = fakePlatform;

    expect(await capturePlugin.getPlatformVersion(), '42');
  });
}
