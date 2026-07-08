import 'package:flutter/material.dart';

class FirstPage extends StatelessWidget {
  const FirstPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout Home'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            const Icon(
              Icons.timer_outlined,
              size: 72,
              color: Colors.white70,
            ),
            const SizedBox(height: 20),
            const Text(
              'Immersive Workout Timer',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Launch the workout screen from here. Run the app once from main.dart, then use this button instead of trying to run page files directly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/workout'),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Open Workout Timer'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/workout'),
              icon: const Icon(Icons.fitness_center_rounded),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Start Training'),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
