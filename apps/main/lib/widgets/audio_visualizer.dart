import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:math' as math;

/// A widget that draws a smooth waveform of raw audio bytes
/// (from the microphone or any audio source).
class AudioVisualizer extends StatelessWidget {
  /// Raw byte data from an audio stream (16-bit, little-endian).
  final List<int> rawAudioData;

  const AudioVisualizer({
    Key? key,
    required this.rawAudioData,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: WaveformPainter(rawAudioData),
      child: Container(
        height: 200,
        width: double.infinity,
      ),
    );
  }
}

/// A custom painter that converts raw bytes → int16 samples,
/// optionally smooths them, and draws a "water-ripple" style
/// waveform using quadratic Bézier curves.
class WaveformPainter extends CustomPainter {
  final List<int> rawBytes;

  WaveformPainter(this.rawBytes);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Convert bytes to int16 samples
    final samples = _bytesToSamples(rawBytes);
    if (samples.isEmpty) return;

    // 2. Convert to double
    List<double> doubleSamples = samples.map((s) => s.toDouble()).toList();

    // 3. Multi-pass smoothing with a windowed average
    //    Increasing passes or windowSize will drastically smooth out spikes.
    doubleSamples =
        _multiPassMovingAverage(doubleSamples, windowSize: 16, passes: 2);

    // 4. Exponential smoothing to further dampen abrupt changes
    //    alpha < 0.5 => heavier smoothing
    doubleSamples = _exponentialSmooth(doubleSamples, alpha: 0.2);

    // 5. Rolling normalization: we track a rolling max amplitude
    //    to stabilize large spikes over time.
    doubleSamples = _rollingNormalize(doubleSamples, windowSize: 200);

    // 6. Build the path and draw it
    _drawSmoothFilledWave(canvas, size, doubleSamples);
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) => true;

  // ---------------------------------------------------------------------------
  // RAW BYTES → INT16
  // ---------------------------------------------------------------------------
  List<int> _bytesToSamples(List<int> raw) {
    final samples = <int>[];
    final byteData = ByteData.sublistView(Uint8List.fromList(raw));
    for (int i = 0; i < raw.length; i += 2) {
      samples.add(byteData.getInt16(i, Endian.little));
    }
    return samples;
  }

  // ---------------------------------------------------------------------------
  // SMOOTHING METHODS
  // ---------------------------------------------------------------------------

  /// 3A. Multi-pass moving average filter
  /// Each pass runs a moving average of `windowSize`.
  /// The larger windowSize or number of passes, the smoother (but less detailed).
  List<double> _multiPassMovingAverage(List<double> data,
      {int windowSize = 8, int passes = 1}) {
    var current = data;
    for (int p = 0; p < passes; p++) {
      current = _movingAverage(current, windowSize);
    }
    return current;
  }

  /// A single-pass moving average.
  List<double> _movingAverage(List<double> data, int windowSize) {
    if (windowSize <= 1) return data;

    final smoothed = <double>[];
    for (int i = 0; i < data.length; i++) {
      double sum = 0;
      int count = 0;
      for (int j = i; j < i + windowSize && j < data.length; j++) {
        sum += data[j];
        count++;
      }
      smoothed.add(sum / math.max(count, 1));
    }
    return smoothed;
  }

  /// 4. Exponential smoothing: smooths out changes over time.
  /// alpha in [0..1]. Smaller alpha => heavier smoothing.
  List<double> _exponentialSmooth(List<double> data, {double alpha = 0.2}) {
    if (data.isEmpty) return data;
    final output = <double>[];
    double? previous;
    for (final value in data) {
      if (previous == null) {
        previous = value;
      } else {
        previous = alpha * value + (1 - alpha) * previous;
      }
      output.add(previous);
    }
    return output;
  }

  // ---------------------------------------------------------------------------
  // NORMALIZATION
  // ---------------------------------------------------------------------------

  /// 5. Rolling normalization: we compute a local max amplitude over a
  /// "sliding window" and use that to scale the samples. This stabilizes
  /// large spikes, instead of normalizing everything by the absolute max
  /// in a single frame.
  List<double> _rollingNormalize(List<double> data, {int windowSize = 100}) {
    if (data.isEmpty) return data;

    // We'll build an array of local maxima
    final localMax = <double>[];
    for (int i = 0; i < data.length; i++) {
      // Look up to `windowSize` samples around i
      double windowPeak = 0;
      for (int j = i; j < i + windowSize && j < data.length; j++) {
        windowPeak = math.max(windowPeak, data[j].abs());
      }
      localMax.add(windowPeak);
    }

    // Now scale each sample by 1/localMax[i], but avoid dividing by zero
    final normalized = <double>[];
    for (int i = 0; i < data.length; i++) {
      final peak = localMax[i];
      if (peak > 0) {
        normalized.add(data[i] / peak);
      } else {
        normalized.add(0);
      }
    }
    return normalized;
  }

  // ---------------------------------------------------------------------------
  // DRAWING
  // ---------------------------------------------------------------------------

  /// 6. Actually draw a smooth filled wave with a gradient fill and a stroke.
  void _drawSmoothFilledWave(Canvas canvas, Size size, List<double> data) {
    if (data.isEmpty) return;

    // Prepare points
    final points = <Offset>[];
    final midY = size.height / 2.0;
    final stepX = size.width / math.max(data.length - 1, 1);

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      // data is in [-1..1], scale to [-midY..midY], then flip so +1 => top of wave
      final y = midY - (data[i] * midY);
      points.add(Offset(x, y));
    }

    // Build a smooth wave path with quadratic Bézier
    final wavePath = Path();
    wavePath.moveTo(points.first.dx, points.first.dy);

    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final current = points[i];
      final midX = (prev.dx + current.dx) / 2;
      final midY = (prev.dy + current.dy) / 2;
      wavePath.quadraticBezierTo(prev.dx, prev.dy, midX, midY);
    }
    // Line to the last point
    wavePath.lineTo(points.last.dx, points.last.dy);

    // Fill path
    final fillPath = Path.from(wavePath)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF77BBFF),
          Color(0xFF0066CC),
        ],
      ).createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // Stroke for wave highlight
    final strokePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawPath(wavePath, strokePaint);
  }
}
