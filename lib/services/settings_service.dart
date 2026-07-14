import 'dart:convert';

import 'package:my_app/models/workout_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _kMaxWorkoutSets = 50;

class AppSettings {
  const AppSettings({
    required this.config,
    required this.voiceCueEnabled,
    required this.hapticCueEnabled,
    required this.muteVoiceWhileMusicPlays,
    required this.voiceCueVolume,
    required this.voiceCueRate,
  });

  final WorkoutConfig config;
  final bool voiceCueEnabled;
  final bool hapticCueEnabled;
  final bool muteVoiceWhileMusicPlays;
  final double voiceCueVolume;
  final double voiceCueRate;

  static AppSettings defaults() {
    return AppSettings(
      config: WorkoutConfig.defaults,
      voiceCueEnabled: true,
      hapticCueEnabled: true,
      muteVoiceWhileMusicPlays: true,
      voiceCueVolume: 1.0,
      voiceCueRate: 0.52,
    );
  }
}

class WorkoutInsights {
  const WorkoutInsights({
    required this.displayName,
    required this.profileImagePath,
    required this.totalWorkouts,
    required this.totalSeconds,
    required this.currentStreakDays,
    required this.bestStreakDays,
    this.lastWorkoutAt,
  });

  final String displayName;
  final String profileImagePath;
  final int totalWorkouts;
  final int totalSeconds;
  final int currentStreakDays;
  final int bestStreakDays;
  final DateTime? lastWorkoutAt;

  static const WorkoutInsights defaults = WorkoutInsights(
    displayName: 'Athlete',
    profileImagePath: '',
    totalWorkouts: 0,
    totalSeconds: 0,
    currentStreakDays: 0,
    bestStreakDays: 0,
  );
}

class WorkoutSessionEntry {
  const WorkoutSessionEntry({
    required this.completedAt,
    required this.durationSeconds,
    required this.sets,
    required this.workSeconds,
    required this.restSeconds,
    required this.intensity,
    this.workoutType,
    this.completedIntervals,
    this.estimatedVo2ImprovementPct,
    this.badgeTitle,
  });

  final DateTime completedAt;
  final int durationSeconds;
  final int sets;
  final int workSeconds;
  final int restSeconds;
  final WorkoutIntensity intensity;
  final String? workoutType;
  final int? completedIntervals;
  final double? estimatedVo2ImprovementPct;
  final String? badgeTitle;

  Map<String, dynamic> toJson() {
    return {
      'completedAt': completedAt.millisecondsSinceEpoch,
      'durationSeconds': durationSeconds,
      'sets': sets,
      'workSeconds': workSeconds,
      'restSeconds': restSeconds,
      'intensity': intensity.index,
      'workoutType': workoutType,
      'completedIntervals': completedIntervals,
      'estimatedVo2ImprovementPct': estimatedVo2ImprovementPct,
      'badgeTitle': badgeTitle,
    };
  }

  static WorkoutSessionEntry fromJson(Map<String, dynamic> json) {
    final intensityIndex = (json['intensity'] as num?)?.toInt() ?? WorkoutIntensity.medium.index;
    return WorkoutSessionEntry(
      completedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['completedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      sets: (json['sets'] as num?)?.toInt() ?? WorkoutConfig.defaults.sets,
      workSeconds: (json['workSeconds'] as num?)?.toInt() ?? WorkoutConfig.defaults.workSeconds,
      restSeconds: (json['restSeconds'] as num?)?.toInt() ?? WorkoutConfig.defaults.restSeconds,
      intensity: WorkoutIntensity.values[intensityIndex.clamp(0, WorkoutIntensity.values.length - 1)],
      workoutType: json['workoutType'] as String?,
      completedIntervals: (json['completedIntervals'] as num?)?.toInt(),
      estimatedVo2ImprovementPct: (json['estimatedVo2ImprovementPct'] as num?)?.toDouble(),
      badgeTitle: json['badgeTitle'] as String?,
    );
  }
}

class SettingsService {
  Future<WorkoutBuilderResumeSession?> loadWorkoutBuilderResumeSession() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_kWorkoutBuilderResumeSession);
    if (encoded == null || encoded.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        return null;
      }

      return WorkoutBuilderResumeSession.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveWorkoutBuilderResumeSession(WorkoutBuilderResumeSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kWorkoutBuilderResumeSession,
      jsonEncode(session.toJson()),
    );
  }

  Future<void> clearWorkoutBuilderResumeSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kWorkoutBuilderResumeSession);
  }

  Future<List<WorkoutBuilderRoutine>> loadWorkoutBuilderRoutines() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_kWorkoutBuilderRoutines);
    if (encoded == null || encoded.trim().isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) {
        return const [];
      }

      final routines = decoded
          .whereType<Map>()
          .map(
            (raw) => WorkoutBuilderRoutine.fromJson(
              Map<String, dynamic>.from(raw),
            ),
          )
          .toList(growable: false)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return routines;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveWorkoutBuilderRoutine(WorkoutBuilderRoutine routine) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadWorkoutBuilderRoutines();

    final index = existing.indexWhere((entry) => entry.id == routine.id);
    final next = [...existing];
    if (index >= 0) {
      next[index] = routine;
    } else {
      next.insert(0, routine);
    }

    await prefs.setString(
      _kWorkoutBuilderRoutines,
      jsonEncode(next.map((entry) => entry.toJson()).toList(growable: false)),
    );
  }

  Future<void> deleteWorkoutBuilderRoutine(String routineId) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadWorkoutBuilderRoutines();
    final next = existing.where((entry) => entry.id != routineId).toList(growable: false);

    await prefs.setString(
      _kWorkoutBuilderRoutines,
      jsonEncode(next.map((entry) => entry.toJson()).toList(growable: false)),
    );
  }

  Future<List<CommunityWorkout>> loadCommunityWorkouts() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_kCommunityWorkouts);
    if (encoded == null || encoded.trim().isEmpty) {
      final seeded = await _seedCommunityWorkouts();
      await saveCommunityWorkouts(seeded);
      return seeded;
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) {
        final seeded = await _seedCommunityWorkouts();
        await saveCommunityWorkouts(seeded);
        return seeded;
      }

      final workouts = decoded
          .whereType<Map>()
          .map((raw) => CommunityWorkout.fromJson(Map<String, dynamic>.from(raw)))
          .toList(growable: false);

      if (workouts.isEmpty) {
        final seeded = await _seedCommunityWorkouts();
        await saveCommunityWorkouts(seeded);
        return seeded;
      }

      return workouts;
    } catch (_) {
      final seeded = await _seedCommunityWorkouts();
      await saveCommunityWorkouts(seeded);
      return seeded;
    }
  }

  Future<void> saveCommunityWorkouts(List<CommunityWorkout> workouts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kCommunityWorkouts,
      jsonEncode(workouts.map((entry) => entry.toJson()).toList(growable: false)),
    );
  }

  Future<CommunityWorkout?> publishCommunityWorkout(PublishCommunityWorkoutInput input) async {
    final cleanedTitle = input.title.trim();
    if (cleanedTitle.isEmpty || input.routine.exercises.isEmpty) {
      return null;
    }

    final insights = await loadInsights();
    final username = insights.displayName.trim().isEmpty
        ? 'Athlete'
        : insights.displayName.trim();

    final workout = CommunityWorkout(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      creatorId: _kLocalCreatorId,
      creatorUsername: username,
      creatorAvatarPath: insights.profileImagePath,
      title: cleanedTitle,
      description: input.description.trim(),
      category: input.category.trim().isEmpty ? 'General' : input.category.trim(),
      difficulty: input.difficulty,
      tags: input.tags,
      coverImagePath: input.coverImagePath,
      exercises: input.routine.exercises,
      createdAt: DateTime.now(),
      downloads: 0,
      likes: 0,
      favorites: 0,
      shares: 0,
      ratingsCount: 0,
      ratingsTotal: 0,
      isLiked: false,
      isFavorited: false,
      isSaved: false,
      comments: const [],
      isFollowingCreator: false,
    );

    final workouts = await loadCommunityWorkouts();
    final next = [workout, ...workouts];
    await saveCommunityWorkouts(next);
    return workout;
  }

  Future<List<CommunityWorkout>> toggleCommunityLike(String workoutId) async {
    return _updateCommunityWorkout(workoutId, (entry) {
      if (entry.isLiked) {
        return entry.copyWith(isLiked: false, likes: (entry.likes - 1).clamp(0, 1 << 30));
      }
      return entry.copyWith(isLiked: true, likes: entry.likes + 1);
    });
  }

  Future<List<CommunityWorkout>> toggleCommunityFavorite(String workoutId) async {
    return _updateCommunityWorkout(workoutId, (entry) {
      if (entry.isFavorited) {
        return entry.copyWith(
          isFavorited: false,
          favorites: (entry.favorites - 1).clamp(0, 1 << 30),
        );
      }
      return entry.copyWith(isFavorited: true, favorites: entry.favorites + 1);
    });
  }

  Future<List<CommunityWorkout>> incrementCommunityShare(String workoutId) async {
    return _updateCommunityWorkout(workoutId, (entry) {
      return entry.copyWith(shares: entry.shares + 1);
    });
  }

  Future<List<CommunityWorkout>> rateCommunityWorkout(String workoutId, int stars) async {
    final normalized = stars.clamp(1, 5);
    return _updateCommunityWorkout(workoutId, (entry) {
      final previous = entry.userRating;
      if (previous == null) {
        return entry.copyWith(
          userRating: normalized,
          ratingsCount: entry.ratingsCount + 1,
          ratingsTotal: entry.ratingsTotal + normalized,
        );
      }
      return entry.copyWith(
        userRating: normalized,
        ratingsTotal: entry.ratingsTotal - previous + normalized,
      );
    });
  }

  Future<List<CommunityWorkout>> addCommunityComment(String workoutId, String message) async {
    final cleanedMessage = message.trim();
    if (cleanedMessage.isEmpty) {
      return loadCommunityWorkouts();
    }

    final insights = await loadInsights();
    final username = insights.displayName.trim().isEmpty
        ? 'Athlete'
        : insights.displayName.trim();

    return _updateCommunityWorkout(workoutId, (entry) {
      return entry.copyWith(
        comments: [
          CommunityComment(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            authorUsername: username,
            message: cleanedMessage,
            createdAt: DateTime.now(),
          ),
          ...entry.comments,
        ],
      );
    });
  }

  Future<List<CommunityWorkout>> toggleFollowCreator(String creatorId) async {
    final prefs = await SharedPreferences.getInstance();
    final workouts = await loadCommunityWorkouts();
    final currentlyFollowing = workouts.any(
      (entry) => entry.creatorId == creatorId && entry.isFollowingCreator,
    );
    final shouldFollow = !currentlyFollowing;
    final next = workouts
        .map((entry) {
          if (entry.creatorId != creatorId) {
            return entry;
          }
          return entry.copyWith(isFollowingCreator: shouldFollow);
        })
        .toList(growable: false);

      final followerCounts = _decodeIntMap(prefs.getString(_kCreatorFollowerCounts));
      final currentFollowers = followerCounts[creatorId] ?? 0;
      followerCounts[creatorId] = shouldFollow
        ? currentFollowers + 1
        : (currentFollowers - 1).clamp(0, 1 << 30);

    await saveCommunityWorkouts(next);
      await prefs.setString(_kCreatorFollowerCounts, jsonEncode(followerCounts));
    return next;
  }

  Future<List<CommunityWorkout>> saveCommunityWorkoutToMyWorkouts(String workoutId) async {
    final workouts = await loadCommunityWorkouts();
    CommunityWorkout? target;
    for (final entry in workouts) {
      if (entry.id == workoutId) {
        target = entry;
        break;
      }
    }
    if (target == null) {
      return workouts;
    }

    final routine = WorkoutBuilderRoutine(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: target.title,
      createdAt: DateTime.now(),
      exercises: target.exercises,
    );
    await saveWorkoutBuilderRoutine(routine);

    final next = workouts
        .map((entry) {
          if (entry.id != workoutId) {
            return entry;
          }
          return entry.copyWith(isSaved: true, downloads: entry.downloads + 1);
        })
        .toList(growable: false);
    await saveCommunityWorkouts(next);
    return next;
  }

  Future<CreatorCommunityStats> loadCreatorCommunityStats(String creatorId) async {
    final workouts = await loadCommunityWorkouts();
    final prefs = await SharedPreferences.getInstance();
    final followerCounts = _decodeIntMap(prefs.getString(_kCreatorFollowerCounts));
    final creatorWorkouts = workouts.where((entry) => entry.creatorId == creatorId).toList();
    if (creatorWorkouts.isEmpty) {
      return const CreatorCommunityStats(
        creatorId: 'unknown',
        username: 'Creator',
        profileImagePath: '',
        totalPublished: 0,
        followers: 0,
        totalDownloads: 0,
        totalShares: 0,
        likesReceived: 0,
        fiveStarRatings: 0,
        badges: [],
      );
    }

    final username = creatorWorkouts.first.creatorUsername;
    final profileImagePath = creatorWorkouts.first.creatorAvatarPath;
    final totalPublished = creatorWorkouts.length;
    final derivedFollowers = creatorWorkouts.any((entry) => entry.isFollowingCreator) ? 1 : 0;
    final followers = (followerCounts[creatorId] ?? 0) > derivedFollowers
        ? (followerCounts[creatorId] ?? 0)
        : derivedFollowers;
    final totalDownloads = creatorWorkouts.fold<int>(0, (sum, entry) => sum + entry.downloads);
    final totalShares = creatorWorkouts.fold<int>(0, (sum, entry) => sum + entry.shares);
    final likesReceived = creatorWorkouts.fold<int>(0, (sum, entry) => sum + entry.likes);
    final fiveStarRatings = creatorWorkouts.fold<int>(0, (sum, entry) {
      if (entry.userRating == 5) {
        return sum + 1;
      }
      return sum;
    });

    final badges = <String>[];
    if (totalPublished >= 1) {
      badges.add('First Published Workout');
    }
    if (totalDownloads >= 100) {
      badges.add('100 Downloads');
    }
    if (fiveStarRatings >= 50) {
      badges.add('50 Five-Star Ratings');
    }
    if (likesReceived >= 250 || totalDownloads >= 300) {
      badges.add('Top Creator');
    }

    return CreatorCommunityStats(
      creatorId: creatorId,
      username: username,
      profileImagePath: profileImagePath,
      totalPublished: totalPublished,
      followers: followers,
      totalDownloads: totalDownloads,
      totalShares: totalShares,
      likesReceived: likesReceived,
      fiveStarRatings: fiveStarRatings,
      badges: badges,
    );
  }

  Future<int> loadAppLifetimeDays({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _epochDay(now ?? DateTime.now());
    final firstOpenDay = prefs.getInt(_kFirstOpenEpochDay);
    if (firstOpenDay == null) {
      await prefs.setInt(_kFirstOpenEpochDay, today);
      return 1;
    }

    if (today <= firstOpenDay) {
      return 1;
    }

    return today - firstOpenDay + 1;
  }

  Map<String, int> _decodeIntMap(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) {
      return <String, int>{};
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        return <String, int>{};
      }

      return decoded.map<String, int>((key, value) {
        return MapEntry(
          key.toString(),
          (value as num?)?.toInt() ?? 0,
        );
      });
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<CreatorCommunityStats> loadMyCommunityStats() async {
    return loadCreatorCommunityStats(_kLocalCreatorId);
  }

  Future<List<CommunityWorkout>> _updateCommunityWorkout(
    String workoutId,
    CommunityWorkout Function(CommunityWorkout entry) updater,
  ) async {
    final workouts = await loadCommunityWorkouts();
    final next = workouts
        .map((entry) => entry.id == workoutId ? updater(entry) : entry)
        .toList(growable: false);
    await saveCommunityWorkouts(next);
    return next;
  }

  Future<List<CommunityWorkout>> _seedCommunityWorkouts() async {
    final now = DateTime.now();
    const seedExercisesA = [
      WorkoutBuilderExercise(name: 'Jump Rope Sprint', workSeconds: 45, restSeconds: 20),
      WorkoutBuilderExercise(name: 'Burpees', workSeconds: 40, restSeconds: 20),
      WorkoutBuilderExercise(name: 'Mountain Climbers', workSeconds: 45, restSeconds: 20),
      WorkoutBuilderExercise(name: 'Skater Hops', workSeconds: 35, restSeconds: 20),
    ];

    const seedExercisesB = [
      WorkoutBuilderExercise(name: 'Goblet Squat', workSeconds: 50, restSeconds: 30),
      WorkoutBuilderExercise(name: 'Push-Up', workSeconds: 45, restSeconds: 30),
      WorkoutBuilderExercise(name: 'Romanian Deadlift', workSeconds: 50, restSeconds: 30),
      WorkoutBuilderExercise(name: 'Plank Hold', workSeconds: 60, restSeconds: 20),
    ];

    return [
      CommunityWorkout(
        id: 'seed.power.$_kSeedVersion',
        creatorId: 'coach.ava',
        creatorUsername: 'CoachAva',
        creatorAvatarPath: '',
        title: 'Power Blast HIIT',
        description: 'Fast-paced full-body HIIT to spike heart rate and burn calories quickly.',
        category: 'HIIT',
        difficulty: WorkoutDifficulty.intermediate,
        tags: const ['HIIT', 'Cardio', 'Fat Loss', 'Full Body', 'Home'],
        coverImagePath: '',
        exercises: seedExercisesA,
        createdAt: now.subtract(const Duration(days: 1)),
        downloads: 112,
        likes: 68,
        favorites: 23,
        shares: 14,
        ratingsCount: 49,
        ratingsTotal: 224,
        isLiked: false,
        isFavorited: false,
        isSaved: false,
        comments: [
          CommunityComment(
            id: 'c.seed.1',
            authorUsername: 'Maya',
            message: 'Perfect for my lunch break.',
            createdAt: DateTime(2026, 7, 10),
          ),
        ],
        isFollowingCreator: false,
      ),
      CommunityWorkout(
        id: 'seed.strength.$_kSeedVersion',
        creatorId: 'nick.fit',
        creatorUsername: 'NickFitLab',
        creatorAvatarPath: '',
        title: 'Strength Builder Circuit',
        description: 'Balanced strength routine for legs, chest, posterior chain, and core.',
        category: 'Strength',
        difficulty: WorkoutDifficulty.beginner,
        tags: const ['Strength', 'Core', 'Legs', 'Gym'],
        coverImagePath: '',
        exercises: seedExercisesB,
        createdAt: now.subtract(const Duration(days: 4)),
        downloads: 86,
        likes: 51,
        favorites: 31,
        shares: 9,
        ratingsCount: 38,
        ratingsTotal: 166,
        isLiked: false,
        isFavorited: false,
        isSaved: false,
        comments: [
          CommunityComment(
            id: 'c.seed.2',
            authorUsername: 'Rami',
            message: 'Simple and effective.',
            createdAt: DateTime(2026, 7, 8),
          ),
        ],
        isFollowingCreator: false,
      ),
    ];
  }

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = AppSettings.defaults();

    final intensityIndex = prefs.getInt(_kIntensityIndex) ?? defaults.config.intensity.index;
    final intensity = WorkoutIntensity.values[intensityIndex.clamp(0, WorkoutIntensity.values.length - 1)];

    final config = WorkoutConfig(
      sets: (prefs.getInt(_kSets) ?? defaults.config.sets).clamp(1, _kMaxWorkoutSets),
      workSeconds: prefs.getInt(_kWorkSeconds) ?? defaults.config.workSeconds,
      restSeconds: prefs.getInt(_kRestSeconds) ?? defaults.config.restSeconds,
      warmupSeconds: prefs.getInt(_kWarmupSeconds) ?? defaults.config.warmupSeconds,
      cooldownSeconds: prefs.getInt(_kCooldownSeconds) ?? defaults.config.cooldownSeconds,
      intensity: intensity,
      finalRestSeconds: prefs.getInt(_kFinalRestSeconds) ?? defaults.config.finalRestSeconds,
      program: WorkoutProgram.values[
        (prefs.getInt(_kProgramIndex) ?? defaults.config.program.index).clamp(
          0,
          WorkoutProgram.values.length - 1,
        )
      ],
    );

    return AppSettings(
      config: config,
      voiceCueEnabled: prefs.getBool(_kVoiceCueEnabled) ?? defaults.voiceCueEnabled,
      hapticCueEnabled: prefs.getBool(_kHapticCueEnabled) ?? defaults.hapticCueEnabled,
      muteVoiceWhileMusicPlays:
          prefs.getBool(_kMuteVoiceWhileMusicPlays) ?? defaults.muteVoiceWhileMusicPlays,
      voiceCueVolume: prefs.getDouble(_kVoiceCueVolume) ?? defaults.voiceCueVolume,
      voiceCueRate: prefs.getDouble(_kVoiceCueRate) ?? defaults.voiceCueRate,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_kSets, settings.config.sets);
    await prefs.setInt(_kWorkSeconds, settings.config.workSeconds);
    await prefs.setInt(_kRestSeconds, settings.config.restSeconds);
    await prefs.setInt(_kWarmupSeconds, settings.config.warmupSeconds);
    await prefs.setInt(_kCooldownSeconds, settings.config.cooldownSeconds);
    await prefs.setInt(_kIntensityIndex, settings.config.intensity.index);
    await prefs.setInt(_kFinalRestSeconds, settings.config.finalRestSeconds);
    await prefs.setInt(_kProgramIndex, settings.config.program.index);

    await prefs.setBool(_kVoiceCueEnabled, settings.voiceCueEnabled);
    await prefs.setBool(_kHapticCueEnabled, settings.hapticCueEnabled);
    await prefs.setBool(_kMuteVoiceWhileMusicPlays, settings.muteVoiceWhileMusicPlays);
    await prefs.setDouble(_kVoiceCueVolume, settings.voiceCueVolume);
    await prefs.setDouble(_kVoiceCueRate, settings.voiceCueRate);
  }

  Future<WorkoutInsights> loadInsights() async {
    final prefs = await SharedPreferences.getInstance();

    final lastWorkoutMillis = prefs.getInt(_kLastWorkoutMillis);
    return WorkoutInsights(
      displayName: prefs.getString(_kDisplayName) ?? WorkoutInsights.defaults.displayName,
      profileImagePath: prefs.getString(_kProfileImagePath) ?? WorkoutInsights.defaults.profileImagePath,
      totalWorkouts: prefs.getInt(_kTotalWorkouts) ?? 0,
      totalSeconds: prefs.getInt(_kTotalSeconds) ?? 0,
      currentStreakDays: prefs.getInt(_kCurrentStreakDays) ?? 0,
      bestStreakDays: prefs.getInt(_kBestStreakDays) ?? 0,
      lastWorkoutAt: lastWorkoutMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastWorkoutMillis),
    );
  }

  Future<void> saveDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = name.trim();
    await prefs.setString(
      _kDisplayName,
      cleaned.isEmpty ? WorkoutInsights.defaults.displayName : cleaned,
    );
  }

  Future<void> saveProfileImagePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = path.trim();
    if (cleaned.isEmpty) {
      await prefs.remove(_kProfileImagePath);
      return;
    }
    await prefs.setString(_kProfileImagePath, cleaned);
  }

  Future<List<WorkoutSessionEntry>> loadRecentSessions({int limit = 7}) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_kRecentSessions);
    if (encoded == null || encoded.trim().isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) {
        return const [];
      }

      final sessions = decoded
          .whereType<Map>()
          .map((raw) => WorkoutSessionEntry.fromJson(Map<String, dynamic>.from(raw)))
          .toList()
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

      return sessions.take(limit).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<bool> shouldSendMissedWorkoutReminder({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final current = now ?? DateTime.now();
    final todayEpochDay = _epochDay(current);
    final lastReminderDay = prefs.getInt(_kLastReminderEpochDay);
    // Daily reminder guard: allow at most one reminder per calendar day.
    return lastReminderDay != todayEpochDay;
  }

  Future<void> markReminderSent({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final current = now ?? DateTime.now();
    await prefs.setInt(_kLastReminderEpochDay, _epochDay(current));
  }

  Future<void> recordWorkoutCompletion(
    int durationSeconds, {
    DateTime? when,
    WorkoutConfig? config,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = when ?? DateTime.now();

    final totalWorkouts = prefs.getInt(_kTotalWorkouts) ?? 0;
    final totalSeconds = prefs.getInt(_kTotalSeconds) ?? 0;
    final currentStreak = prefs.getInt(_kCurrentStreakDays) ?? 0;
    final bestStreak = prefs.getInt(_kBestStreakDays) ?? 0;
    final lastDay = prefs.getInt(_kLastWorkoutEpochDay);
    final todayDay = _epochDay(now);

    var nextStreak = currentStreak;
    if (lastDay == null) {
      nextStreak = 1;
    } else if (todayDay == lastDay) {
      nextStreak = currentStreak == 0 ? 1 : currentStreak;
    } else if (todayDay == lastDay + 1) {
      nextStreak = currentStreak + 1;
    } else {
      nextStreak = 1;
    }

    await prefs.setInt(_kTotalWorkouts, totalWorkouts + 1);
    await prefs.setInt(_kTotalSeconds, totalSeconds + durationSeconds.clamp(0, 86400));
    await prefs.setInt(_kCurrentStreakDays, nextStreak);
    await prefs.setInt(_kBestStreakDays, nextStreak > bestStreak ? nextStreak : bestStreak);
    await prefs.setInt(_kLastWorkoutEpochDay, todayDay);
    await prefs.setInt(_kLastWorkoutMillis, now.millisecondsSinceEpoch);

    final recent = await loadRecentSessions(limit: 30);
    final activeConfig = config ?? WorkoutConfig.defaults;
    final isVo2Max = _isVo2MaxFourByFour(activeConfig);
    final estimatedGainPct = isVo2Max ? 1.2 : null;
    final updated = [
      WorkoutSessionEntry(
        completedAt: now,
        durationSeconds: durationSeconds.clamp(0, 86400),
        sets: activeConfig.sets,
        workSeconds: activeConfig.workSeconds,
        restSeconds: activeConfig.restSeconds,
        intensity: activeConfig.intensity,
        workoutType: _workoutTypeFor(activeConfig, isVo2Max: isVo2Max),
        completedIntervals: isVo2Max ? activeConfig.sets : null,
        estimatedVo2ImprovementPct: estimatedGainPct,
        badgeTitle: isVo2Max ? 'Completed 4x4 VO2max session' : null,
      ),
      ...recent,
    ].take(30).map((entry) => entry.toJson()).toList(growable: false);

    await prefs.setString(_kRecentSessions, jsonEncode(updated));
  }

  int _epochDay(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  }

  bool _isVo2MaxFourByFour(WorkoutConfig config) {
    return config.program == WorkoutProgram.vo2max ||
        (config.sets == 4 &&
        config.workSeconds == 240 &&
        config.restSeconds == 180 &&
        config.warmupSeconds == 600 &&
        config.cooldownSeconds >= 300);
  }

  String _workoutTypeFor(WorkoutConfig config, {required bool isVo2Max}) {
    if (isVo2Max) {
      return 'vo2max_4x4';
    }

    switch (config.program) {
      case WorkoutProgram.hiitCardio:
        return 'hiit_cardio';
      case WorkoutProgram.tabataCardio:
        return 'tabata_cardio';
      case WorkoutProgram.cardio:
        return 'cardio';
      case WorkoutProgram.pushUps:
        return 'push_ups';
      case WorkoutProgram.calisthenics:
        return 'calisthenics_15';
      case WorkoutProgram.vo2max:
        return 'vo2max_4x4';
      case WorkoutProgram.custom:
        return 'custom';
    }
  }
}

const _kSets = 'settings.sets';
const _kWorkSeconds = 'settings.workSeconds';
const _kRestSeconds = 'settings.restSeconds';
const _kWarmupSeconds = 'settings.warmupSeconds';
const _kCooldownSeconds = 'settings.cooldownSeconds';
const _kIntensityIndex = 'settings.intensityIndex';
const _kFinalRestSeconds = 'settings.finalRestSeconds';
const _kProgramIndex = 'settings.programIndex';

const _kVoiceCueEnabled = 'settings.voiceCueEnabled';
const _kHapticCueEnabled = 'settings.hapticCueEnabled';
const _kMuteVoiceWhileMusicPlays = 'settings.muteVoiceWhileMusicPlays';
const _kVoiceCueVolume = 'settings.voiceCueVolume';
const _kVoiceCueRate = 'settings.voiceCueRate';

const _kDisplayName = 'insights.displayName';
const _kProfileImagePath = 'insights.profileImagePath';
const _kTotalWorkouts = 'insights.totalWorkouts';
const _kTotalSeconds = 'insights.totalSeconds';
const _kCurrentStreakDays = 'insights.currentStreakDays';
const _kBestStreakDays = 'insights.bestStreakDays';
const _kLastWorkoutEpochDay = 'insights.lastWorkoutEpochDay';
const _kLastWorkoutMillis = 'insights.lastWorkoutMillis';
const _kRecentSessions = 'insights.recentSessions';
const _kLastReminderEpochDay = 'reminders.lastReminderEpochDay';
const _kWorkoutBuilderRoutines = 'profile.workoutBuilderRoutines';
const _kWorkoutBuilderResumeSession = 'profile.workoutBuilderResumeSession';
const _kCommunityWorkouts = 'community.workouts';
const _kCreatorFollowerCounts = 'community.creatorFollowerCounts';
const _kLocalCreatorId = 'user.local';
const _kFirstOpenEpochDay = 'app.firstOpenEpochDay';
const _kSeedVersion = '1';
