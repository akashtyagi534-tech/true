import 'package:flutter/material.dart';
import 'recording_screen.dart';

void main() {
  runApp(const TruthVerifyApp());
}

class TruthVerifyApp extends StatelessWidget {
  const TruthVerifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Truth Lens Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D4ED8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const RecordingScreen(),
    );
  }
}
