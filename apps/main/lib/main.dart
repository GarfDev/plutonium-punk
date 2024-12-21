import 'package:capture/capture.dart';
import 'package:flutter/material.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final capture = Capture();
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Audio Visualizer')),
        body: Column(
          children: [
            AudioVisualizer(amplitudeStream: capture.amplitudeStream),
            ElevatedButton(
              onPressed: capture.startAudioCapture,
              child: Text('Start Capture'),
            ),
            ElevatedButton(
              onPressed: capture.stopAudioCapture,
              child: Text('Stop Capture'),
            ),
          ],
        ),
      ),
    );
  }
}

class AudioVisualizer extends StatefulWidget {
  final Stream<List<double>> amplitudeStream;

  const AudioVisualizer({required this.amplitudeStream, Key? key})
      : super(key: key);

  @override
  _AudioVisualizerState createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer> {
  List<double> _amplitudes = [];

  @override
  void initState() {
    super.initState();
    widget.amplitudeStream.listen((amplitudes) {
      setState(() {
        _amplitudes = amplitudes;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: WaveformPainter(_amplitudes),
      child: Container(height: 200, width: double.infinity),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> amplitudes;

  WaveformPainter(this.amplitudes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path();
    final middle = size.height / 2;
    final widthPerSample = size.width / amplitudes.length;

    if (amplitudes.isNotEmpty) {
      path.moveTo(0, middle);
      for (int i = 0; i < amplitudes.length; i++) {
        final x = i * widthPerSample;
        final y = middle - amplitudes[i] * middle;
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
