import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audio_recorder/audio_recorder.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Recorder Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const AudioCaptureScreen(),
    );
  }
}

class AudioCaptureScreen extends StatefulWidget {
  const AudioCaptureScreen({super.key});

  @override
  State<AudioCaptureScreen> createState() => _AudioCaptureScreenState();
}

class _AudioCaptureScreenState extends State<AudioCaptureScreen> {
  bool _isRecording = false;
  StreamSubscription<List<int>>? _audioSubscription;
  int _lastDataLength = 0;

  @override
  void dispose() {
    _audioSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      // Optionally specify an outputPath if you want to record to a file.
      // For now, let's just stream audio data and not write to a file:
      await AudioRecorder.startRecording();

      _audioSubscription = AudioRecorder.audioStream.listen((data) {
        setState(() {
          _lastDataLength = data.length;
        });
        // Here, `data` is raw PCM audio data. You can do processing or debugging.
        // print("Received PCM data of length: ${data.length}");
      });

      setState(() {
        _isRecording = true;
      });
    } catch (e) {
      print("Error starting recording: $e");
    }
  }

  Future<void> _stopRecording() async {
    try {
      await AudioRecorder.stopRecording();
      await _audioSubscription?.cancel();
      setState(() {
        _isRecording = false;
        _lastDataLength = 0;
      });
    } catch (e) {
      print("Error stopping recording: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _isRecording
        ? 'Recording in progress... Last data length: $_lastDataLength bytes'
        : 'Not recording';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Recorder Demo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text(statusText),
            const SizedBox(height: 20),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _isRecording ? null : _startRecording,
                  child: const Text('Start Recording'),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: _isRecording ? _stopRecording : null,
                  child: const Text('Stop Recording'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
