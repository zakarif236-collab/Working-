import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:my_app/models/workout_models.dart';

class WorkoutController extends ChangeNotifier {
  WorkoutController({WorkoutConfig? initialConfig})
      : _config = initialConfig ?? WorkoutConfig.defaults {
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
    _config = newConfig;
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

    if (_config.workSeconds < 5 || _config.restSeconds < 5) {
      _error = 'Work and rest must be at least 5 seconds.';
      return false;
    }

    return true;
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
          label: 'Warmup',
        ),
      );
    }

    for (var i = 1; i <= _config.sets; i++) {
      nextTimeline.add(
        WorkoutPhase(
          type: WorkoutPhaseType.work,
          durationSeconds: _config.workSeconds,
          label: 'Push',
          setNumber: i,
        ),
      );

      if (i != _config.sets && _config.restSeconds > 0) {
        nextTimeline.add(
          WorkoutPhase(
            type: WorkoutPhaseType.rest,
            durationSeconds: _config.restSeconds,
            label: 'Recover',
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
          label: 'Cooldown',
        ),
      );
    }

    _timeline = nextTimeline;
    _phaseIndex = 0;
    _remainingSeconds = _timeline.isEmpty ? 0 : _timeline.first.durationSeconds;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
