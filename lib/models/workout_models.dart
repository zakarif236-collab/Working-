enum WorkoutIntensity { low, medium, high }

enum WorkoutPhaseType { warmup, work, rest, cooldown, complete }

class WorkoutConfig {
  const WorkoutConfig({
    required this.sets,
    required this.workSeconds,
    required this.restSeconds,
    required this.warmupSeconds,
    required this.cooldownSeconds,
    required this.intensity,
  });

  final int sets;
  final int workSeconds;
  final int restSeconds;
  final int warmupSeconds;
  final int cooldownSeconds;
  final WorkoutIntensity intensity;

  WorkoutConfig copyWith({
    int? sets,
    int? workSeconds,
    int? restSeconds,
    int? warmupSeconds,
    int? cooldownSeconds,
    WorkoutIntensity? intensity,
  }) {
    return WorkoutConfig(
      sets: sets ?? this.sets,
      workSeconds: workSeconds ?? this.workSeconds,
      restSeconds: restSeconds ?? this.restSeconds,
      warmupSeconds: warmupSeconds ?? this.warmupSeconds,
      cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
      intensity: intensity ?? this.intensity,
    );
  }

  static const WorkoutConfig defaults = WorkoutConfig(
    sets: 4,
    workSeconds: 45,
    restSeconds: 20,
    warmupSeconds: 20,
    cooldownSeconds: 20,
    intensity: WorkoutIntensity.medium,
  );
}

class WorkoutPhase {
  const WorkoutPhase({
    required this.type,
    required this.durationSeconds,
    required this.label,
    this.setNumber,
  });

  final WorkoutPhaseType type;
  final int durationSeconds;
  final String label;
  final int? setNumber;
}
