import 'dart:async';
import 'dart:typed_data';

import 'package:capture/capture.dart';
import 'package:deepgram_speech_to_text/deepgram_speech_to_text.dart';

const API_KEY = 'fed7fb01a64f39523fc8876fda59076b22dcf116';

class AudioService {
  final Capture _capture = Capture();
  final Deepgram _deepgram = Deepgram(API_KEY);

  final StreamController<List<int>> _audioController =
      StreamController.broadcast();
  final StreamController<String> _transcriptionController =
      StreamController.broadcast();

  Stream<List<int>> get audioStream => _audioController.stream;
  Stream<String> get transcriptionStream => _transcriptionController.stream;

  bool _isCapturing = false;
  late DeepgramLiveListener _listener;

  AudioService() {
    _listener = _deepgram.listen.liveListener(
      _capture.rawAudioStream,
      encoding: 'linear16',
      sampleRate: 48000,
    );

    _listener.stream.listen((result) {
      _transcriptionController.add(result.transcript ?? '');
    }, onError: (err) {
      print("Deepgram Stream Error: $err");
    });

    print(_capture.rawAudioStream);

    _capture.rawAudioStream.listen((chunk) {
      final List<int> parsedSamples = [];
      final byteData = ByteData.sublistView(Uint8List.fromList(chunk));

      for (int i = 0; i < chunk.length; i += 2) {
        final sample = byteData.getInt16(i, Endian.little);
        parsedSamples.add(sample);
      }

      _audioController.add(parsedSamples);
    }, onError: (err) {
      print("Audio Stream Error: $err");
    });
  }

  Future<void> startCapture() async {
    if (_isCapturing) return;
    _isCapturing = true;

    await _capture.startAudioCapture();
    await _listener.start();
    print("Capture started.");
  }

  Future<void> stopCapture() async {
    if (!_isCapturing) return;
    _isCapturing = false;

    await _capture.stopAudioCapture();
    await _listener.close();
    _audioController.close();
    _transcriptionController.close();
    print("Capture stopped.");
  }
}
