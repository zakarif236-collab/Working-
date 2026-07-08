import 'package:flutter/material.dart';
import 'package:my_app/pages/first_page.dart';
import 'package:my_app/pages/workout_timer_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFFFF5A5F),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Immersive Workout Timer',
      theme: base.copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D121C),
      ),
      routes: {
        '/workout': (_) => const WorkoutTimerPage(),
      },
      home: const FirstPage(),
    );
  }
}