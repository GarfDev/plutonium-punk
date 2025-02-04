import 'dart:async';

import 'package:deepgram_speech_to_text/deepgram_speech_to_text.dart';
import 'package:flutter/foundation.dart';

class DeepgramService {
  final Deepgram _deepgram;
  final StreamController<String> _transcriptionController =
      StreamController.broadcast();

  /// The Deepgram live listener, created once we start listening to audio.
  DeepgramLiveListener? _listener;

  /// Public stream of transcribed text (updates continuously).
  Stream<String> get transcriptionStream => _transcriptionController.stream;

  bool _isListening = false;

  /// Constructor requires your Deepgram API key.
  DeepgramService(String apiKey) : _deepgram = Deepgram(apiKey);

  /// Start feeding audio samples into Deepgram's streaming endpoint.
  /// [audioStream] should be the same format expected by Deepgram
  /// (linear16, 48kHz in this example).
  Future<void> startListening(Stream<List<int>> audioStream) async {
    if (_isListening) return;
    _isListening = true;

    _listener = _deepgram.listen.liveListener(
      audioStream,
      encoding: 'linear16',
      sampleRate: 48000,
    );

    _listener!.stream.listen((result) {
      final transcript = result.transcript ?? '';
      _transcriptionController.add(transcript);
    }, onError: (err) {
      debugPrint("DeepgramService - Error: $err");
    });

    // Actually start streaming to Deepgram
    await _listener!.start();
    debugPrint("DeepgramService - Listening started.");
  }

  /// Stop feeding data to Deepgram and close the stream.
  Future<void> stopListening() async {
    if (!_isListening) return;
    _isListening = false;

    await _listener?.close();
    debugPrint("DeepgramService - Listening stopped.");
  }

  /// Dispose of controller resources when done.
  Future<void> dispose() async {
    await _transcriptionController.close();
  }
}
