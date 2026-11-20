import 'package:flutter/material.dart';
import 'api_service.dart';
import 'home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.init();
  runApp(const TruthLensApp());
}

class TruthLensApp extends StatelessWidget {
  const TruthLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Truth Lens Pro',
      debugShowCheckedModeBanner: false,
      theme: buildTruthLensTheme(),
      home: const HomeScreen(),
    );
  }
}
