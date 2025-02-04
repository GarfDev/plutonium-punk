import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Import local services
import 'package:main/services/audio.dart';
import 'package:main/services/deepgram.dart';

// Import widgets
import 'widgets/audio_visualizer.dart';

// Import constants
import 'constants/secrects.dart';

void main() async {
  // For tray_manager to work smoothly with Flutter,
  // ensure the binding is initialized first:
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize your services
  final audioService = AudioService();
  final deepgramService = DeepgramService(DEEPGRAM_API_KEY);

  runApp(
    MultiProvider(
      providers: [
        Provider<AudioService>.value(value: audioService),
        Provider<DeepgramService>.value(value: deepgramService),
        StreamProvider<List<int>>(
          create: (_) => audioService.audioStream,
          initialData: const [],
        ),
        StreamProvider<String>(
          create: (_) => deepgramService.transcriptionStream,
          initialData: '',
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio + Deepgram Demo',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Audio Capture & Transcription'),
        ),
        body: const AudioVisualizerScreen(),
      ),
    );
  }
}

class AudioVisualizerScreen extends StatelessWidget {
  const AudioVisualizerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Watch raw audio bytes
    final rawAudioData = context.watch<List<int>>();
    // 2. Watch the latest transcription
    final transcript = context.watch<String>();

    // Access the service instances
    final audioService = context.read<AudioService>();
    final deepgramService = context.read<DeepgramService>();

    return Column(
      children: [
        // Display transcript
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Transcript: $transcript',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),

        // The smooth, wave-like visualization
        // Expanded(
        //   child: AudioVisualizer(rawAudioData: rawAudioData),
        // ),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton(
              onPressed: () async {
                try {
                  await audioService.startCapture();
                  await deepgramService.startListening(
                    audioService.audioStream,
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to start capture: $e')),
                  );
                }
              },
              child: const Text('Start Capture'),
            ),
            ElevatedButton(
              onPressed: () async {
                await deepgramService.stopListening();
                await audioService.stopCapture();
              },
              child: const Text('Stop Capture'),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
