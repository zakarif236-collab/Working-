import 'package:flutter/material.dart';
import 'package:my_app/models/workout_models.dart';
import 'package:my_app/services/settings_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final SettingsService _settingsService = SettingsService();
  WorkoutBuilderResumeSession? _resumeSession;

  @override
  void initState() {
    super.initState();
    _refreshResumeSession();
  }

  Future<void> _refreshResumeSession() async {
    final session = await _settingsService.loadWorkoutBuilderResumeSession();
    if (!mounted) {
      return;
    }

    setState(() {
      _resumeSession = session;
    });
  }

  Future<void> _openWorkoutBuilder(BuildContext context) async {
    await Navigator.of(context).pushNamed('/workout-builder');
    await _refreshResumeSession();
  }

  Future<void> _openMyWorkouts(BuildContext context) async {
    await Navigator.of(context).pushNamed('/my-workouts');
    await _refreshResumeSession();
  }

  Future<void> _resumeLastWorkout(BuildContext context) async {
    final session = _resumeSession;
    if (session == null) {
      return;
    }

    await Navigator.of(context).pushNamed(
      '/workout-builder-player',
      arguments: session,
    );
    await _refreshResumeSession();
  }

  Future<void> _openCommunity(BuildContext context) async {
    await Navigator.of(context).pushNamed('/community');
    await _refreshResumeSession();
  }

  Future<void> _openTrainingLauncher(BuildContext context) async {
    final navigator = Navigator.of(context);
    final selectedMode = await showModalBottomSheet<_TrainingMode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _TrainingModeSheet(
          onSelected: (mode) => Navigator.of(sheetContext).pop(mode),
        );
      },
    );

    if (selectedMode == null) {
      return;
    }

    await navigator.pushNamed(
      '/workout',
      arguments: _presetForMode(selectedMode),
    );
    await _refreshResumeSession();
  }

  WorkoutConfig _presetForMode(_TrainingMode mode) {
    switch (mode) {
      case _TrainingMode.hiitCardio:
        return const WorkoutConfig(
          sets: 5,
          workSeconds: 40,
          restSeconds: 20,
          warmupSeconds: 180,
          cooldownSeconds: 120,
          intensity: WorkoutIntensity.high,
          program: WorkoutProgram.hiitCardio,
        );
      case _TrainingMode.tabataCardio:
        return const WorkoutConfig(
          sets: 8,
          workSeconds: 20,
          restSeconds: 10,
          warmupSeconds: 180,
          cooldownSeconds: 180,
          intensity: WorkoutIntensity.high,
          finalRestSeconds: 10,
          program: WorkoutProgram.tabataCardio,
        );
      case _TrainingMode.vo2max:
        return const WorkoutConfig(
          sets: 4,
          workSeconds: 240,
          restSeconds: 180,
          warmupSeconds: 600,
          cooldownSeconds: 300,
          intensity: WorkoutIntensity.high,
          finalRestSeconds: 180,
          program: WorkoutProgram.vo2max,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResume = _resumeSession != null;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF141B2D), Color(0xFF0A1020), Color(0xFF1A2439)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              children: [
                const Spacer(flex: 5),
                _HomeActionButton(
                  label: 'Quick Start',
                  icon: Icons.play_circle_fill_rounded,
                  backgroundColor: const Color(0xFFF2A6A6),
                  foregroundColor: const Color(0xFF2A1A1A),
                  onPressed: () => _openTrainingLauncher(context),
                ),
                const SizedBox(height: 18),
                _HomeActionButton(
                  label: 'Workout Builder',
                  icon: Icons.bolt_rounded,
                  backgroundColor: const Color(0xFF86E3A4),
                  foregroundColor: const Color(0xFF102817),
                  onPressed: () => _openWorkoutBuilder(context),
                ),
                const SizedBox(height: 18),
                _HomeActionButton(
                  label: 'My Workouts',
                  icon: Icons.library_books_rounded,
                  backgroundColor: const Color(0xFF9BC4FF),
                  foregroundColor: const Color(0xFF10213D),
                  onPressed: () => _openMyWorkouts(context),
                ),
                const SizedBox(height: 18),
                _HomeActionButton(
                  label: 'Community',
                  icon: Icons.public_rounded,
                  backgroundColor: const Color(0xFFF5A97D),
                  foregroundColor: const Color(0xFF361E10),
                  onPressed: () => _openCommunity(context),
                ),
                if (canResume) ...[
                  const SizedBox(height: 18),
                  _HomeActionButton(
                    label: 'Resume Last Workout',
                    icon: Icons.playlist_play_rounded,
                    backgroundColor: const Color(0xFFF9C97A),
                    foregroundColor: const Color(0xFF2D2108),
                    onPressed: () => _resumeLastWorkout(context),
                  ),
                ],
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeActionButton extends StatelessWidget {
  const _HomeActionButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(label),
        ),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(72),
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

enum _TrainingMode { hiitCardio, tabataCardio, vo2max }

class _TrainingModeSheet extends StatelessWidget {
  const _TrainingModeSheet({required this.onSelected});

  final ValueChanged<_TrainingMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF101A2B),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white24),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const Text(
              'Start Training',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pick a mode and jump straight into your next session.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            _TrainingModeTile(
              icon: Icons.monitor_heart_rounded,
              title: 'VO2max 4x4 (Quick Start)',
              subtitle: '10 min warm-up, 4x(4:00 push / 3:00 recover), 5-10 min cool-down',
              highlighted: true,
              onTap: () => onSelected(_TrainingMode.vo2max),
            ),
            _TrainingModeTile(
              icon: Icons.flash_on_rounded,
              title: 'HIIT Cardio',
              subtitle: '3 min warm-up, 5x(40s work / 20s rest), 2 min cool-down',
              onTap: () => onSelected(_TrainingMode.hiitCardio),
            ),
            _TrainingModeTile(
              icon: Icons.timer_rounded,
              title: 'Tabata Cardio (10 min)',
              subtitle: '2-3 min warm-up, 8x(20s work / 10s rest), 2-3 min cool-down',
              onTap: () => onSelected(_TrainingMode.tabataCardio),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainingModeTile extends StatelessWidget {
  const _TrainingModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: highlighted
            ? const Color(0xFF2A426E).withValues(alpha: 0.62)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: highlighted ? const Color(0xFF9BC4FF) : Colors.white24,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: highlighted
                        ? const Color(0xFF9BC4FF)
                        : const Color(0xFFF2A6A6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: const Color(0xFF18253E), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (highlighted)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Text(
                      'Focus',
                      style: TextStyle(
                        color: Color(0xFF9BC4FF),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
