import 'package:flutter/material.dart';
import 'dart:typed_data';

import 'package:capture/capture.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: AudioCaptureExample());
  }
}

class AudioCaptureExample extends StatefulWidget {
  @override
  _AudioCaptureExampleState createState() => _AudioCaptureExampleState();
}

class _AudioCaptureExampleState extends State<AudioCaptureExample> {
  final _audioCapture = Capture();
  Uint8List? _audioData;

  @override
  void initState() {
    super.initState();
    _audioCapture.audioStream.listen((data) {
      setState(() {
        _audioData = data;
      });
    });
  }

  void _startCapture() {
    _audioCapture.startAudioCapture();
  }

  void _stopCapture() {
    _audioCapture.stopAudioCapture();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Audio Capture Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Audio Data Length: ${_audioData?.length ?? 0} bytes'),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                    onPressed: _startCapture, child: Text('Start Capture')),
                SizedBox(width: 20),
                ElevatedButton(
                    onPressed: _stopCapture, child: Text('Stop Capture')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
