import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_app/models/workout_models.dart';
import 'package:my_app/services/cue_service.dart';
import 'package:my_app/services/settings_service.dart';

enum _BuilderPhaseType { work, rest, complete }

class _BuilderPhase {
  const _BuilderPhase({
    required this.type,
    required this.durationSeconds,
    required this.exerciseIndex,
    required this.exercise,
    required this.label,
  });

  final _BuilderPhaseType type;
  final int durationSeconds;
  final int exerciseIndex;
  final WorkoutBuilderExercise exercise;
  final String label;
}

class WorkoutBuilderPlayerPage extends StatefulWidget {
  const WorkoutBuilderPlayerPage({super.key});

  @override
  State<WorkoutBuilderPlayerPage> createState() => _WorkoutBuilderPlayerPageState();
}

class _WorkoutBuilderPlayerPageState extends State<WorkoutBuilderPlayerPage> {
  final CueService _cueService = CueService();
  final SettingsService _settingsService = SettingsService();

  WorkoutBuilderRoutine? _routine;
  List<_BuilderPhase> _timeline = const [];
  Timer? _ticker;

  int _phaseIndex = 0;
  int _remainingSeconds = 0;
  bool _isRunning = false;
  bool _didInit = false;
  bool _restoredFromResume = false;

  bool _voiceCueEnabled = true;
  bool _hapticCueEnabled = true;
  bool _didAnnounceCompletion = false;
  int _lastObservedPhaseIndex = -1;
  int _lastAnnouncedSeconds = -1;

  @override
  void initState() {
    super.initState();
    _initializeCueSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) {
      return;
    }
    _didInit = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    WorkoutBuilderRoutine? routine;
    WorkoutBuilderResumeSession? resumeSession;

    if (args is WorkoutBuilderResumeSession) {
      routine = args.routine;
      resumeSession = args;
      _restoredFromResume = true;
    } else if (args is WorkoutBuilderRoutine) {
      routine = args;
    }

    if (routine == null) {
      _showMessage('Workout data missing.');
      return;
    }

    _routine = routine;
    _timeline = _buildTimeline(routine);
    _phaseIndex = 0;
    _remainingSeconds = _timeline.isEmpty ? 0 : _timeline.first.durationSeconds;

    if (resumeSession != null && _timeline.isNotEmpty) {
      final maxIndex = _timeline.length - 1;
      _phaseIndex = resumeSession.phaseIndex.clamp(0, maxIndex);
      final currentDuration = _timeline[_phaseIndex].durationSeconds;
      _remainingSeconds = resumeSession.remainingSeconds.clamp(0, currentDuration);
      if (_remainingSeconds == 0) {
        _remainingSeconds = currentDuration;
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_isComplete || !_hasProgressToResume) {
      unawaited(_settingsService.clearWorkoutBuilderResumeSession());
    } else {
      unawaited(_persistResumeSnapshot());
    }
    _cueService.dispose();
    super.dispose();
  }

  bool get _hasProgressToResume {
    if (_timeline.isEmpty || _isComplete) {
      return false;
    }

    final currentDuration = _currentPhase.durationSeconds;
    final progressedCurrent = _remainingSeconds < currentDuration;
    return _phaseIndex > 0 || progressedCurrent;
  }

  Future<void> _persistResumeSnapshot() async {
    final routine = _routine;
    if (routine == null || !_hasProgressToResume) {
      await _settingsService.clearWorkoutBuilderResumeSession();
      return;
    }

    final snapshot = WorkoutBuilderResumeSession(
      routine: routine,
      phaseIndex: _phaseIndex,
      remainingSeconds: _remainingSeconds,
      savedAt: DateTime.now(),
    );

    await _settingsService.saveWorkoutBuilderResumeSession(snapshot);
  }

  Future<void> _initializeCueSettings() async {
    try {
      final settings = await _settingsService.load();
      await _cueService.updateSettings(
        volume: settings.voiceCueVolume,
        speechRate: settings.voiceCueRate,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _voiceCueEnabled = _cueService.supportsVoiceCues && settings.voiceCueEnabled;
        _hapticCueEnabled = settings.hapticCueEnabled;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not load cue settings. Using defaults.');
    }
  }

  String _phaseVoiceCueText(_BuilderPhase phase) {
    if (phase.type == _BuilderPhaseType.rest) {
      return 'Rest';
    }
    return phase.exercise.name;
  }

  Future<void> _handleWorkoutCues() async {
    if (_isRunning && _phaseIndex != _lastObservedPhaseIndex) {
      _lastObservedPhaseIndex = _phaseIndex;
      if (!_isComplete) {
        if (_hapticCueEnabled) {
          await HapticFeedback.mediumImpact();
        }
        await _cueService.playPhaseCompletionBeep();
        if (_voiceCueEnabled) {
          try {
            await _cueService.announcePhase(_phaseVoiceCueText(_currentPhase));
          } on CueServiceException catch (e) {
            _showMessage(e.message);
          }
        }
      }
    }

    if (_isRunning && _remainingSeconds != _lastAnnouncedSeconds) {
      _lastAnnouncedSeconds = _remainingSeconds;
      if (_remainingSeconds > 0 && _remainingSeconds <= 5) {
        if (_hapticCueEnabled) {
          if (_remainingSeconds <= 3) {
            await HapticFeedback.lightImpact();
          } else {
            await HapticFeedback.selectionClick();
          }
        }
        if (_voiceCueEnabled) {
          try {
            await _cueService.speakCount(_remainingSeconds, shouldSpeak: true);
          } on CueServiceException catch (e) {
            _showMessage(e.message);
          }
        }
      }
    }

    if (_isComplete && !_didAnnounceCompletion) {
      _didAnnounceCompletion = true;
      if (_hapticCueEnabled) {
        await HapticFeedback.heavyImpact();
      }
      await _cueService.playWorkoutCompletionBeep();
      if (_voiceCueEnabled) {
        try {
          await _cueService.announceCompletion();
        } on CueServiceException catch (e) {
          _showMessage(e.message);
        }
      }
      return;
    }

    if (!_isComplete) {
      _didAnnounceCompletion = false;
    }
  }

  List<_BuilderPhase> _buildTimeline(WorkoutBuilderRoutine routine) {
    final phases = <_BuilderPhase>[];

    for (var i = 0; i < routine.exercises.length; i++) {
      final exercise = routine.exercises[i];
      phases.add(
        _BuilderPhase(
          type: _BuilderPhaseType.work,
          durationSeconds: exercise.workSeconds,
          exerciseIndex: i,
          exercise: exercise,
          label: exercise.name,
        ),
      );

      if (exercise.restSeconds > 0) {
        phases.add(
          _BuilderPhase(
            type: _BuilderPhaseType.rest,
            durationSeconds: exercise.restSeconds,
            exerciseIndex: i,
            exercise: exercise,
            label: 'Rest',
          ),
        );
      }
    }

    return phases;
  }

  _BuilderPhase get _currentPhase {
    if (_timeline.isEmpty || _phaseIndex < 0 || _phaseIndex >= _timeline.length) {
      return _BuilderPhase(
        type: _BuilderPhaseType.complete,
        durationSeconds: 0,
        exerciseIndex: 0,
        exercise: const WorkoutBuilderExercise(
          name: 'Complete',
          workSeconds: 0,
          restSeconds: 0,
        ),
        label: 'Workout Complete',
      );
    }
    return _timeline[_phaseIndex];
  }

  bool get _isComplete => _currentPhase.type == _BuilderPhaseType.complete;

  int get _totalSeconds => _timeline.fold<int>(0, (sum, phase) => sum + phase.durationSeconds);

  int get _elapsedSeconds {
    final beforeCurrent = _timeline
        .take(_phaseIndex.clamp(0, _timeline.length))
        .fold<int>(0, (sum, phase) => sum + phase.durationSeconds);

    final currentElapsed =
        (_currentPhase.durationSeconds - _remainingSeconds).clamp(0, _currentPhase.durationSeconds);

    return beforeCurrent + currentElapsed;
  }

  double get _phaseProgress {
    final total = _currentPhase.durationSeconds;
    if (total <= 0) {
      return 1;
    }
    return ((total - _remainingSeconds) / total).clamp(0, 1);
  }

  double get _totalProgress {
    final total = _totalSeconds;
    if (total <= 0) {
      return 0;
    }
    return (_elapsedSeconds / total).clamp(0, 1);
  }

  void _start() {
    if (_timeline.isEmpty) {
      return;
    }

    if (_isComplete) {
      _phaseIndex = 0;
      _remainingSeconds = _timeline.first.durationSeconds;
    }

    _remainingSeconds = _remainingSeconds == 0
        ? _currentPhase.durationSeconds
        : _remainingSeconds;

    _ticker?.cancel();
    setState(() {
      _isRunning = true;
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isRunning) {
        return;
      }

      setState(() {
        _remainingSeconds -= 1;
        if (_remainingSeconds <= 0) {
          _moveToNextPhase();
        }
      });

      unawaited(_handleWorkoutCues());
      unawaited(_persistResumeSnapshot());
    });

    unawaited(_handleWorkoutCues());
    unawaited(_persistResumeSnapshot());
  }

  void _pause() {
    _ticker?.cancel();
    setState(() {
      _isRunning = false;
    });
    unawaited(_persistResumeSnapshot());
  }

  void _stopAndReset() {
    _ticker?.cancel();
    setState(() {
      _isRunning = false;
      _phaseIndex = 0;
      _remainingSeconds = _timeline.isEmpty ? 0 : _timeline.first.durationSeconds;
      _lastAnnouncedSeconds = -1;
      _lastObservedPhaseIndex = -1;
      _didAnnounceCompletion = false;
    });
    unawaited(_settingsService.clearWorkoutBuilderResumeSession());
  }

  void _skip() {
    if (_timeline.isEmpty || _isComplete) {
      return;
    }
    setState(_moveToNextPhase);
    unawaited(_handleWorkoutCues());
    unawaited(_persistResumeSnapshot());
  }

  void _moveToNextPhase() {
    if (_phaseIndex < _timeline.length - 1) {
      _phaseIndex += 1;
      _remainingSeconds = _timeline[_phaseIndex].durationSeconds;
      return;
    }

    _phaseIndex = _timeline.length;
    _remainingSeconds = 0;
    _isRunning = false;
    _ticker?.cancel();
    unawaited(_settingsService.clearWorkoutBuilderResumeSession());
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    if (minutes == 0) {
      return '${remainder}s';
    }
    return '${minutes}m ${remainder.toString().padLeft(2, '0')}s';
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routine = _routine;
    if (routine == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workout')),
        body: const Center(
          child: Text('Unable to load workout.'),
        ),
      );
    }

    final current = _currentPhase;
    final isRest = current.type == _BuilderPhaseType.rest;

    return Scaffold(
      appBar: AppBar(
        title: Text(routine.name),
        backgroundColor: const Color(0xFF101A2B),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF141B2D), Color(0xFF0A1020), Color(0xFF1A2439)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isComplete
                        ? 'Workout Complete'
                        : isRest
                            ? 'Rest'
                            : current.exercise.name,
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (_restoredFromResume)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: _MetaChip(
                            icon: Icons.refresh_rounded,
                            label: 'Resumed',
                          ),
                        ),
                      _MetaChip(
                        icon: Icons.list_alt_rounded,
                        label: '${routine.exercises.length} exercises',
                      ),
                      const SizedBox(width: 8),
                      _MetaChip(
                        icon: Icons.timer_rounded,
                        label: _formatDuration(_totalSeconds),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: _phaseProgress,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      _remainingSeconds.toString(),
                      style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Center(
                    child: Text(
                      isRest ? 'Rest period' : 'Work interval',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _totalProgress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(99),
                    color: const Color(0xFF5EC6FF),
                    backgroundColor: Colors.white24,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Progress: ${_formatDuration(_elapsedSeconds)} / ${_formatDuration(_totalSeconds)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (!_isComplete)
              isRest
                  ? const _RestPhaseMessageCard(
                      message: 'Take a deep breath. Recover and get ready for the next push.',
                    )
                  : _ExerciseMediaPreview(path: current.exercise.mediaPath),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _skip,
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _stopAndReset,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isRunning ? _pause : _start,
                    icon: Icon(
                      _isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                    label: Text(_isRunning ? 'Pause' : (_isComplete ? 'Restart' : 'Start')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Timeline',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ..._timeline.asMap().entries.map((entry) {
              final index = entry.key;
              final phase = entry.value;
              final active = index == _phaseIndex;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF2A426E).withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active ? const Color(0xFF9BC4FF) : Colors.white24,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      phase.type == _BuilderPhaseType.work
                          ? Icons.flash_on_rounded
                          : Icons.self_improvement_rounded,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        phase.type == _BuilderPhaseType.work
                            ? 'Work: ${phase.exercise.name}'
                            : 'Rest: ${phase.exercise.name}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${phase.durationSeconds}s',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _ExerciseMediaPreview extends StatelessWidget {
  const _ExerciseMediaPreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final cleaned = path.trim();
    if (cleaned.isEmpty) {
      return Container(
        height: 170,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: Colors.white24),
        ),
        child: const Text(
          'No GIF/image for this exercise',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.file(
        File(cleaned),
        height: 220,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          return Container(
            height: 170,
            alignment: Alignment.center,
            color: Colors.black26,
            child: const Text(
              'Could not load media preview',
              style: TextStyle(color: Colors.white70),
            ),
          );
        },
      ),
    );
  }
}

class _RestPhaseMessageCard extends StatelessWidget {
  const _RestPhaseMessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 170,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFFB8FFE4).withValues(alpha: 0.12),
        border: Border.all(color: const Color(0xFF7FE6BB).withValues(alpha: 0.7)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.self_improvement_rounded, size: 34, color: Color(0xFF7FE6BB)),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
