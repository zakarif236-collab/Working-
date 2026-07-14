import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:my_app/models/workout_models.dart';

const List<String> _calisthenicsExerciseLabels = [
  'Jump Squats',
  'Push-ups + Tap',
  'Bear Crawl',
  'Mountain Climbers',
  'Burpee + Push-up',
  'V-ups',
];

const List<String> _hiitExerciseLabels = [
  'Burpees',
  'Mountain Climbers',
  'Jump Squats',
  'High Knees',
  'Skater Jumps',
];

class WorkoutController extends ChangeNotifier {
  static const int maxSets = 50;

  WorkoutController({WorkoutConfig? initialConfig})
      : _config = _normalizeConfig(initialConfig ?? WorkoutConfig.defaults) {
    _buildTimeline();
  }

  WorkoutConfig _config;
  List<WorkoutPhase> _timeline = const [];
  Timer? _ticker;
  int _phaseIndex = 0;
  int _remainingSeconds = 0;
  bool _isRunning = false;
  String? _error;

  WorkoutConfig get config => _config;
  List<WorkoutPhase> get timeline => _timeline;
  int get phaseIndex => _phaseIndex;
  int get remainingSeconds => _remainingSeconds;
  bool get isRunning => _isRunning;
  String? get error => _error;

  WorkoutPhase get currentPhase {
    if (_timeline.isEmpty) {
      return const WorkoutPhase(
        type: WorkoutPhaseType.complete,
        durationSeconds: 0,
        label: 'Ready',
      );
    }

    if (_phaseIndex < 0 || _phaseIndex >= _timeline.length) {
      return const WorkoutPhase(
        type: WorkoutPhaseType.complete,
        durationSeconds: 0,
        label: 'Complete',
      );
    }

    return _timeline[_phaseIndex];
  }

  double get phaseProgress {
    final total = currentPhase.durationSeconds;
    if (total <= 0) {
      return 1;
    }
    return ((total - _remainingSeconds) / total).clamp(0, 1);
  }

  int get totalWorkoutSeconds =>
      _timeline.fold<int>(0, (sum, phase) => sum + phase.durationSeconds);

  int get elapsedWorkoutSeconds {
    final doneBeforeCurrent = _timeline
        .take(_phaseIndex.clamp(0, _timeline.length))
        .fold<int>(0, (sum, phase) => sum + phase.durationSeconds);

    final currentElapsed =
        (currentPhase.durationSeconds - _remainingSeconds).clamp(0, 1000000);

    return doneBeforeCurrent + currentElapsed;
  }

  double get totalProgress {
    final total = totalWorkoutSeconds;
    if (total == 0) {
      return 0;
    }
    return (elapsedWorkoutSeconds / total).clamp(0, 1);
  }

  bool get isComplete => currentPhase.type == WorkoutPhaseType.complete;

  void updateConfig(WorkoutConfig newConfig) {
    _config = _normalizeConfig(newConfig);
    _error = null;
    stop(reset: true);
    _buildTimeline();
    notifyListeners();
  }

  void start() {
    _error = null;
    if (!_validateConfig()) {
      notifyListeners();
      return;
    }

    if (_timeline.isEmpty) {
      _buildTimeline();
    }

    if (isComplete || _phaseIndex >= _timeline.length) {
      _phaseIndex = 0;
      _remainingSeconds = _timeline.first.durationSeconds;
    }

    _remainingSeconds = _remainingSeconds == 0
        ? currentPhase.durationSeconds
        : _remainingSeconds;

    _ticker?.cancel();
    _isRunning = true;
    notifyListeners();

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isRunning) {
        return;
      }

      _remainingSeconds -= 1;
      if (_remainingSeconds <= 0) {
        _moveToNextPhase();
      }
      notifyListeners();
    });
  }

  void pause() {
    _isRunning = false;
    _ticker?.cancel();
    notifyListeners();
  }

  void stop({bool reset = false}) {
    _isRunning = false;
    _ticker?.cancel();
    if (reset) {
      _phaseIndex = 0;
      _remainingSeconds = _timeline.isEmpty ? 0 : _timeline.first.durationSeconds;
    }
    notifyListeners();
  }

  void skipPhase() {
    if (_timeline.isEmpty || isComplete) {
      return;
    }
    _moveToNextPhase();
    notifyListeners();
  }

  String? takeError() {
    final value = _error;
    _error = null;
    return value;
  }

  bool _validateConfig() {
    if (_config.sets < 1) {
      _error = 'Please choose at least 1 set.';
      return false;
    }

    if (_config.sets > maxSets) {
      _error = 'Please choose at most $maxSets sets.';
      return false;
    }

    if (_config.workSeconds < 5 || _config.restSeconds < 5) {
      _error = 'Work and rest must be at least 5 seconds.';
      return false;
    }

    return true;
  }

  static WorkoutConfig _normalizeConfig(WorkoutConfig config) {
    return config.copyWith(sets: config.sets.clamp(1, maxSets));
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
  }

  void _buildTimeline() {
    final nextTimeline = <WorkoutPhase>[];

    if (_config.warmupSeconds > 0) {
      nextTimeline.add(
        WorkoutPhase(
          type: WorkoutPhaseType.warmup,
          durationSeconds: _config.warmupSeconds,
          label: 'Warm-up',
        ),
      );
    }

    for (var i = 1; i <= _config.sets; i++) {
      nextTimeline.add(
        WorkoutPhase(
          type: WorkoutPhaseType.work,
          durationSeconds: _config.workSeconds,
          label: _workLabelForSet(i),
          setNumber: i,
        ),
      );

      final isLastSet = i == _config.sets;
      final restDuration = isLastSet
          ? _finalRestDurationForLastSet()
          : _config.restSeconds;
      if (restDuration > 0) {
        nextTimeline.add(
          WorkoutPhase(
            type: WorkoutPhaseType.rest,
            durationSeconds: restDuration,
            label: _restLabelForSet(i, isLastSet: isLastSet),
            setNumber: i,
          ),
        );
      }
    }

    if (_config.cooldownSeconds > 0) {
      nextTimeline.add(
        WorkoutPhase(
          type: WorkoutPhaseType.cooldown,
          durationSeconds: _config.cooldownSeconds,
          label: 'Cool-down',
        ),
      );
    }

    _timeline = nextTimeline;
    _phaseIndex = 0;
    _remainingSeconds = _timeline.isEmpty ? 0 : _timeline.first.durationSeconds;
  }

  String _workLabelForSet(int setNumber) {
    if (_config.program == WorkoutProgram.vo2max) {
      return 'Interval $setNumber';
    }

    if (_config.program == WorkoutProgram.hiitCardio) {
      return _hiitExerciseLabels[(setNumber - 1) % _hiitExerciseLabels.length];
    }

    if (_config.program == WorkoutProgram.tabataCardio) {
      return 'Work $setNumber';
    }

    if (_config.program == WorkoutProgram.calisthenics) {
      return _calisthenicsExerciseLabels[(setNumber - 1) % _calisthenicsExerciseLabels.length];
    }
    return 'Push';
  }

  String _restLabelForSet(int setNumber, {required bool isLastSet}) {
    if (_config.program == WorkoutProgram.vo2max) {
      return 'Recovery $setNumber';
    }

    if (_config.program == WorkoutProgram.hiitCardio) {
      return 'Rest $setNumber';
    }

    if (_config.program == WorkoutProgram.tabataCardio) {
      return 'Rest $setNumber';
    }

    if (_config.program == WorkoutProgram.calisthenics) {
      return isLastSet ? 'Transition' : 'Reset';
    }
    return 'Recover';
  }

  int _finalRestDurationForLastSet() {
    if (_config.finalRestSeconds > 0) {
      return _config.finalRestSeconds;
    }

    // VO2max 4x4 convention keeps a final 3-minute recovery before cool-down.
    if (_config.program == WorkoutProgram.vo2max) {
      return _config.restSeconds;
    }

    return 0;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
