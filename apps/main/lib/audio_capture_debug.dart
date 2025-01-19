import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:capture/capture.dart';

class AudioCaptureDebug extends StatefulWidget {
  const AudioCaptureDebug({Key? key}) : super(key: key);

  @override
  _AudioCaptureDebugState createState() => _AudioCaptureDebugState();
}

class _AudioCaptureDebugState extends State<AudioCaptureDebug> {
  final BytesBuilder _pcmBuffer =
      BytesBuilder(); // Accumulator for raw PCM data
  late Capture capture;
  bool _isCapturing = false; // To track capture state

  @override
  void initState() {
    super.initState();
    capture = Capture();
    _initializeAudioStream();
  }

  void _initializeAudioStream() {
    capture.rawAudioStream.listen(
      (chunk) {
        print('Received audio chunk: length=${chunk.length}');
        if (chunk.isNotEmpty) {
          print('First few bytes: ${chunk.take(8).toList()}');
        }
        // Accumulate raw PCM data
        _pcmBuffer.add(chunk);
      },
      onError: (err) {
        print('Error on audio stream: $err');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $err')),
        );
      },
    );
  }

  Future<void> _startCapture() async {
    if (_isCapturing) {
      print("Capture is already running.");
      return;
    }

    print("Starting capture...");
    try {
      await capture.startAudioCapture();
      setState(() {
        _isCapturing = true;
      });
      print("Capture started.");
    } catch (e) {
      print("Error starting capture: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start capture: $e')),
      );
    }
  }

  Future<void> _stopCaptureAndSave() async {
    if (!_isCapturing) {
      print("No capture is running.");
      return;
    }

    print("Stopping capture...");
    try {
      await capture.stopAudioCapture();
      setState(() {
        _isCapturing = false;
      });

      // Write out a WAV file
      final totalSamples =
          _pcmBuffer.length ~/ (2 * (32 ~/ 8)); // 2 channels, 32-bit float
      final header = capture.buildWavHeader(
        totalAudioSamples: totalSamples,
        sampleRate: 48000,
        bitsPerSample: 32,
        channels: 2,
      );

      final durationSeconds = totalSamples / 48000;
      print("Audio duration: $durationSeconds seconds");

      // Combine header + PCM data into a single Uint8List
      final wavBytes = BytesBuilder();
      wavBytes.add(header);
      wavBytes.add(_pcmBuffer.toBytes());

      // Save to a file in the system temp directory
      final directory = await Directory.systemTemp.createTemp('audio_test');
      final filePath = '${directory.path}/test_audio.wav';
      final file = File(filePath);
      await file.writeAsBytes(wavBytes.toBytes());

      print('WAV file saved to: $filePath');
      print('You can open this file in Audacity or another audio player.');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('WAV saved to: $filePath')),
      );

      // Clear PCM buffer for the next capture session
      _pcmBuffer.clear();
    } catch (e) {
      print("Error stopping capture or saving file: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save WAV: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Capture Debug'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _startCapture,
              child: const Text("Start Capture"),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _stopCaptureAndSave,
              child: const Text("Stop Capture & Save WAV"),
            ),
            if (_isCapturing)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  "Capturing audio...",
                  style:
                      TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
