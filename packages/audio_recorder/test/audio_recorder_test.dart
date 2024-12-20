import 'package:flutter_test/flutter_test.dart';
import 'package:audio_recorder/audio_recorder.dart';
import 'package:audio_recorder/audio_recorder_platform_interface.dart';
import 'package:audio_recorder/audio_recorder_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAudioRecorderPlatform
    with MockPlatformInterfaceMixin
    implements AudioRecorderPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final AudioRecorderPlatform initialPlatform = AudioRecorderPlatform.instance;

  test('$MethodChannelAudioRecorder is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAudioRecorder>());
  });

  test('getPlatformVersion', () async {
    AudioRecorder audioRecorderPlugin = AudioRecorder();
    MockAudioRecorderPlatform fakePlatform = MockAudioRecorderPlatform();
    AudioRecorderPlatform.instance = fakePlatform;

    expect(await audioRecorderPlugin.getPlatformVersion(), '42');
  });
}
