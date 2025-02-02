import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:main/AudioService.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        StreamProvider<List<int>>(
          create: (_) => AudioService().audioStream,
          initialData: [],
        ),
        StreamProvider<String>(
          create: (_) => AudioService().transcriptionStream,
          initialData: '',
        ),
      ],
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Audio Visualizer & Transcription')),
        body: AudioVisualizerScreen(),
      ),
    );
  }
}

class AudioVisualizerScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final audioData = context.watch<List<int>>();
    final caption = context.watch<String>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            "CAPTION: $caption",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: AudioVisualizer(audioData: audioData),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton(
              onPressed: () async {
                try {
                  await AudioService().startCapture();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to start capture: $e')),
                  );
                }
              },
              child: Text('Start Capture'),
            ),
            ElevatedButton(
              onPressed: () async {
                await AudioService().stopCapture();
              },
              child: Text('Stop Capture'),
            ),
          ],
        ),
      ],
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
      final maxAmplitude = audioData
          .map((sample) => sample.abs())
          .reduce((a, b) => a > b ? a : b);
      final normalizedSamples = audioData.map((sample) {
        return maxAmplitude > 0 ? sample / maxAmplitude : 0;
      }).toList();

      final widthPerSample = size.width / normalizedSamples.length;

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
