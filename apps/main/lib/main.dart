import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:capture/capture.dart';
import 'package:deepgram_speech_to_text/deepgram_speech_to_text.dart';
import 'package:main/audio_capture_debug.dart';

const API_KEY = 'fed7fb01a64f39523fc8876fda59076b22dcf116';

final STREAM_PARAMS = {
  'detect_language': false, // not supported by streaming API
  'language': 'en',
  // must specify encoding and sample_rate according to the audio stream
  'encoding': 'linear16',
  'sample_rate': 44100,
};

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String caption = '';
  final capture = Capture();

  late Deepgram deepgram;
  late DeepgramLiveListener listener;
  late StreamSubscription<DeepgramListenResult> subscription;
  late StreamSubscription<List<int>> virtualizeSubcription;

  /// This list holds the audio samples (in 16-bit signed integer form)
  final List<int> _audioData = [];

  @override
  void initState() {
    super.initState();
    deepgram = Deepgram(API_KEY);

    listener = deepgram.listen.liveListener(
      capture.rawAudioStream,
      encoding: 'linear16',
      sampleRate: 48000,
    );

    subscription = listener.stream.listen(
      (res) {
        setState(() {
          print("res: ${res}");
          caption = res.transcript ?? '';
        });
        listener.resume();
      },
      onError: (err) {
        listener.resume();
        print("Stream error: $err");
      },
    );

    virtualizeSubcription = capture.rawAudioStream.listen((chunk) {
      final byteData = ByteData.sublistView(Uint8List.fromList(chunk));

      // Parse 16-bit signed samples
      for (int i = 0; i < chunk.length; i += 2) {
        final sample = byteData.getInt16(i, Endian.little);
        _audioData.add(sample);
      }

      // Limit the buffer size
      const maxSamplesForDisplay = 2000;
      if (_audioData.length > maxSamplesForDisplay) {
        _audioData.removeRange(0, _audioData.length - maxSamplesForDisplay);
      }

      setState(() {});
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    virtualizeSubcription.cancel();
    capture.stopAudioCapture();
    listener.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Audio Visualizer & Transcription')),
        // body: AudioCaptureDebug(),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "CAPTION: $caption",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: AudioVisualizer(audioData: _audioData),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    try {
                      print("Starting audio capture...");

                      // Step 1: Start audio capture
                      await capture.startAudioCapture();

                      // Step 2: Start the Deepgram listener
                      await listener.start();

                      listener.stream.listen(
                        (res) {
                          setState(() {
                            print("res: ${res}");
                            caption = res.transcript ?? '';
                          });
                          listener.resume();
                        },
                        onError: (err) {
                          listener.resume();
                          print("Stream error: $err");
                        },
                      );

                      // Step 3: Start the subscription
                      subscription.resume();

                      // Step 4: Start the virtualizeSubcription
                      capture.rawAudioStream.listen((chunk) {
                        final byteData =
                            ByteData.sublistView(Uint8List.fromList(chunk));

                        // Parse 16-bit signed samples
                        for (int i = 0; i < chunk.length; i += 2) {
                          final sample = byteData.getInt16(i, Endian.little);
                          _audioData.add(sample);
                        }

                        // Limit the buffer size
                        const maxSamplesForDisplay = 2000;
                        if (_audioData.length > maxSamplesForDisplay) {
                          _audioData.removeRange(
                              0, _audioData.length - maxSamplesForDisplay);
                        }

                        setState(() {});
                      });
                      print("Audio capture and transcription started.");
                    } catch (e) {
                      print("Failed to start capture: $e");
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to start capture: $e')),
                      );
                    }
                  },
                  child: Text('Start Capture'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await capture.stopAudioCapture();
                    subscription.cancel();
                    await listener.close();
                    print("Capture stopped");
                  },
                  child: Text('Stop Capture'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
            ),
          ],
        ),
      ),
    );
  }
}

class AudioVisualizer extends StatelessWidget {
  final List<int> audioData;

  const AudioVisualizer({required this.audioData, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: WaveformPainter(audioData),
      child: Container(
        height: 200,
        width: double.infinity,
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<int> audioData;

  WaveformPainter(this.audioData);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path();
    final middle = size.height / 2;

    if (audioData.isNotEmpty) {
      // Find the maximum amplitude for normalization
      final maxAmplitude = audioData
          .map((sample) => sample.abs())
          .reduce((a, b) => a > b ? a : b);

      // Normalize all amplitudes to a -1..1 range
      final normalizedSamples = audioData.map((sample) {
        return maxAmplitude > 0 ? sample / maxAmplitude : 0;
      }).toList();

      // Calculate horizontal spacing
      final widthPerSample = size.width / normalizedSamples.length;

      // Start drawing from the center
      path.moveTo(0, middle);
      for (int i = 0; i < normalizedSamples.length; i++) {
        final x = i * widthPerSample;
        final y = middle - normalizedSamples[i] * middle;
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) => true;
}
