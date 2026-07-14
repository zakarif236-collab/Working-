enum WorkoutIntensity { low, medium, high }

enum WorkoutProgram {
  custom,
  hiitCardio,
  tabataCardio,
  cardio,
  pushUps,
  calisthenics,
  vo2max,
}

enum WorkoutPhaseType { warmup, work, rest, cooldown, complete }

class WorkoutConfig {
  const WorkoutConfig({
    required this.sets,
    required this.workSeconds,
    required this.restSeconds,
    required this.warmupSeconds,
    required this.cooldownSeconds,
    required this.intensity,
    this.finalRestSeconds = 0,
    this.program = WorkoutProgram.custom,
  });

  final int sets;
  final int workSeconds;
  final int restSeconds;
  final int warmupSeconds;
  final int cooldownSeconds;
  final WorkoutIntensity intensity;
  final int finalRestSeconds;
  final WorkoutProgram program;

  WorkoutConfig copyWith({
    int? sets,
    int? workSeconds,
    int? restSeconds,
    int? warmupSeconds,
    int? cooldownSeconds,
    WorkoutIntensity? intensity,
    int? finalRestSeconds,
    WorkoutProgram? program,
  }) {
    return WorkoutConfig(
      sets: sets ?? this.sets,
      workSeconds: workSeconds ?? this.workSeconds,
      restSeconds: restSeconds ?? this.restSeconds,
      warmupSeconds: warmupSeconds ?? this.warmupSeconds,
      cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
      intensity: intensity ?? this.intensity,
      finalRestSeconds: finalRestSeconds ?? this.finalRestSeconds,
      program: program ?? this.program,
    );
  }

  static const WorkoutConfig defaults = WorkoutConfig(
    sets: 4,
    workSeconds: 45,
    restSeconds: 20,
    warmupSeconds: 20,
    cooldownSeconds: 20,
    intensity: WorkoutIntensity.medium,
    finalRestSeconds: 0,
    program: WorkoutProgram.custom,
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

class WorkoutBuilderExercise {
  const WorkoutBuilderExercise({
    required this.name,
    required this.workSeconds,
    required this.restSeconds,
    this.mediaPath = '',
  });

  final String name;
  final int workSeconds;
  final int restSeconds;
  final String mediaPath;

  WorkoutBuilderExercise copyWith({
    String? name,
    int? workSeconds,
    int? restSeconds,
    String? mediaPath,
  }) {
    return WorkoutBuilderExercise(
      name: name ?? this.name,
      workSeconds: workSeconds ?? this.workSeconds,
      restSeconds: restSeconds ?? this.restSeconds,
      mediaPath: mediaPath ?? this.mediaPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'workSeconds': workSeconds,
      'restSeconds': restSeconds,
      'mediaPath': mediaPath,
    };
  }

  static WorkoutBuilderExercise fromJson(Map<String, dynamic> json) {
    return WorkoutBuilderExercise(
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Exercise',
      // Legacy routines that still include sets/reps are collapsed to a single
      // timed interval per exercise to match the new interval-builder model.
      workSeconds: ((json['workSeconds'] as num?)?.toInt() ?? 40).clamp(5, 900),
      restSeconds: ((json['restSeconds'] as num?)?.toInt() ?? 20).clamp(0, 900),
      mediaPath: (json['mediaPath'] as String?)?.trim() ?? '',
    );
  }
}

class WorkoutBuilderRoutine {
  const WorkoutBuilderRoutine({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.exercises,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final List<WorkoutBuilderExercise> exercises;

  int get estimatedDurationSeconds {
    var total = 0;
    for (final exercise in exercises) {
      total += exercise.workSeconds;
      total += exercise.restSeconds;
    }
    return total;
  }

  WorkoutBuilderRoutine copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    List<WorkoutBuilderExercise>? exercises,
  }) {
    return WorkoutBuilderRoutine(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      exercises: exercises ?? this.exercises,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'exercises': exercises.map((exercise) => exercise.toJson()).toList(),
    };
  }

  static WorkoutBuilderRoutine fromJson(Map<String, dynamic> json) {
    final rawExercises = json['exercises'];
    final exercises = rawExercises is List
        ? rawExercises
              .whereType<Map>()
              .map(
                (raw) => WorkoutBuilderExercise.fromJson(
                  Map<String, dynamic>.from(raw),
                ),
              )
              .toList(growable: false)
        : const <WorkoutBuilderExercise>[];

    return WorkoutBuilderRoutine(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : DateTime.now().millisecondsSinceEpoch.toString(),
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Untitled Workout',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
      exercises: exercises,
    );
  }
}

class WorkoutBuilderResumeSession {
  const WorkoutBuilderResumeSession({
    required this.routine,
    required this.phaseIndex,
    required this.remainingSeconds,
    required this.savedAt,
  });

  final WorkoutBuilderRoutine routine;
  final int phaseIndex;
  final int remainingSeconds;
  final DateTime savedAt;

  Map<String, dynamic> toJson() {
    return {
      'routine': routine.toJson(),
      'phaseIndex': phaseIndex,
      'remainingSeconds': remainingSeconds,
      'savedAt': savedAt.millisecondsSinceEpoch,
    };
  }

  static WorkoutBuilderResumeSession? fromJson(Map<String, dynamic> json) {
    final rawRoutine = json['routine'];
    if (rawRoutine is! Map) {
      return null;
    }

    final routine = WorkoutBuilderRoutine.fromJson(
      Map<String, dynamic>.from(rawRoutine),
    );

    if (routine.exercises.isEmpty) {
      return null;
    }

    return WorkoutBuilderResumeSession(
      routine: routine,
      phaseIndex: ((json['phaseIndex'] as num?)?.toInt() ?? 0).clamp(0, 10000),
      remainingSeconds: ((json['remainingSeconds'] as num?)?.toInt() ?? 0).clamp(0, 3600),
      savedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['savedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

enum WorkoutDifficulty { beginner, intermediate, advanced }

enum CommunityTabKind { trending, popular, newest, following, favorites }

class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.authorUsername,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String authorUsername;
  final String message;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'authorUsername': authorUsername,
      'message': message,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  static CommunityComment fromJson(Map<String, dynamic> json) {
    return CommunityComment(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : DateTime.now().microsecondsSinceEpoch.toString(),
      authorUsername: (json['authorUsername'] as String?)?.trim().isNotEmpty == true
          ? (json['authorUsername'] as String).trim()
          : 'athlete',
      message: (json['message'] as String?)?.trim().isNotEmpty == true
          ? (json['message'] as String).trim()
          : 'Nice workout!',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class CommunityWorkout {
  const CommunityWorkout({
    required this.id,
    required this.creatorId,
    required this.creatorUsername,
    required this.creatorAvatarPath,
    required this.title,
    required this.description,
    required this.category,
    required this.difficulty,
    required this.tags,
    required this.coverImagePath,
    required this.exercises,
    required this.createdAt,
    required this.downloads,
    required this.likes,
    required this.favorites,
    required this.shares,
    required this.ratingsCount,
    required this.ratingsTotal,
    required this.isLiked,
    required this.isFavorited,
    required this.isSaved,
    required this.comments,
    required this.isFollowingCreator,
    this.userRating,
  });

  final String id;
  final String creatorId;
  final String creatorUsername;
  final String creatorAvatarPath;
  final String title;
  final String description;
  final String category;
  final WorkoutDifficulty difficulty;
  final List<String> tags;
  final String coverImagePath;
  final List<WorkoutBuilderExercise> exercises;
  final DateTime createdAt;
  final int downloads;
  final int likes;
  final int favorites;
  final int shares;
  final int ratingsCount;
  final int ratingsTotal;
  final bool isLiked;
  final bool isFavorited;
  final bool isSaved;
  final int? userRating;
  final List<CommunityComment> comments;
  final bool isFollowingCreator;

  int get estimatedDurationSeconds {
    var total = 0;
    for (final exercise in exercises) {
      total += exercise.workSeconds;
      total += exercise.restSeconds;
    }
    return total;
  }

  double get averageRating {
    if (ratingsCount <= 0 || ratingsTotal <= 0) {
      return 0;
    }
    return ratingsTotal / ratingsCount;
  }

  CommunityWorkout copyWith({
    String? id,
    String? creatorId,
    String? creatorUsername,
    String? creatorAvatarPath,
    String? title,
    String? description,
    String? category,
    WorkoutDifficulty? difficulty,
    List<String>? tags,
    String? coverImagePath,
    List<WorkoutBuilderExercise>? exercises,
    DateTime? createdAt,
    int? downloads,
    int? likes,
    int? favorites,
    int? shares,
    int? ratingsCount,
    int? ratingsTotal,
    bool? isLiked,
    bool? isFavorited,
    bool? isSaved,
    int? userRating,
    bool clearUserRating = false,
    List<CommunityComment>? comments,
    bool? isFollowingCreator,
  }) {
    return CommunityWorkout(
      id: id ?? this.id,
      creatorId: creatorId ?? this.creatorId,
      creatorUsername: creatorUsername ?? this.creatorUsername,
      creatorAvatarPath: creatorAvatarPath ?? this.creatorAvatarPath,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      difficulty: difficulty ?? this.difficulty,
      tags: tags ?? this.tags,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      exercises: exercises ?? this.exercises,
      createdAt: createdAt ?? this.createdAt,
      downloads: downloads ?? this.downloads,
      likes: likes ?? this.likes,
      favorites: favorites ?? this.favorites,
      shares: shares ?? this.shares,
      ratingsCount: ratingsCount ?? this.ratingsCount,
      ratingsTotal: ratingsTotal ?? this.ratingsTotal,
      isLiked: isLiked ?? this.isLiked,
      isFavorited: isFavorited ?? this.isFavorited,
      isSaved: isSaved ?? this.isSaved,
      userRating: clearUserRating ? null : (userRating ?? this.userRating),
      comments: comments ?? this.comments,
      isFollowingCreator: isFollowingCreator ?? this.isFollowingCreator,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'creatorId': creatorId,
      'creatorUsername': creatorUsername,
      'creatorAvatarPath': creatorAvatarPath,
      'title': title,
      'description': description,
      'category': category,
      'difficulty': difficulty.index,
      'tags': tags,
      'coverImagePath': coverImagePath,
      'exercises': exercises.map((exercise) => exercise.toJson()).toList(growable: false),
      'createdAt': createdAt.millisecondsSinceEpoch,
      'downloads': downloads,
      'likes': likes,
      'favorites': favorites,
      'shares': shares,
      'ratingsCount': ratingsCount,
      'ratingsTotal': ratingsTotal,
      'isLiked': isLiked,
      'isFavorited': isFavorited,
      'isSaved': isSaved,
      'userRating': userRating,
      'comments': comments.map((comment) => comment.toJson()).toList(growable: false),
      'isFollowingCreator': isFollowingCreator,
    };
  }

  static CommunityWorkout fromJson(Map<String, dynamic> json) {
    final rawExercises = json['exercises'];
    final exercises = rawExercises is List
        ? rawExercises
              .whereType<Map>()
              .map(
                (raw) => WorkoutBuilderExercise.fromJson(
                  Map<String, dynamic>.from(raw),
                ),
              )
              .toList(growable: false)
        : const <WorkoutBuilderExercise>[];

    final rawTags = json['tags'];
    final tags = rawTags is List
        ? rawTags
              .whereType<String>()
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    final rawComments = json['comments'];
    final comments = rawComments is List
        ? rawComments
              .whereType<Map>()
              .map((raw) => CommunityComment.fromJson(Map<String, dynamic>.from(raw)))
              .toList(growable: false)
        : const <CommunityComment>[];

    final difficultyIndex = (json['difficulty'] as num?)?.toInt() ?? 0;

    return CommunityWorkout(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : DateTime.now().microsecondsSinceEpoch.toString(),
      creatorId: (json['creatorId'] as String?)?.trim().isNotEmpty == true
          ? (json['creatorId'] as String).trim()
          : 'user.local',
      creatorUsername: (json['creatorUsername'] as String?)?.trim().isNotEmpty == true
          ? (json['creatorUsername'] as String).trim()
          : 'athlete',
      creatorAvatarPath: (json['creatorAvatarPath'] as String?)?.trim() ?? '',
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : 'Workout',
      description: (json['description'] as String?)?.trim() ?? '',
      category: (json['category'] as String?)?.trim().isNotEmpty == true
          ? (json['category'] as String).trim()
          : 'General',
      difficulty: WorkoutDifficulty.values[
        difficultyIndex.clamp(0, WorkoutDifficulty.values.length - 1)
      ],
      tags: tags,
      coverImagePath: (json['coverImagePath'] as String?)?.trim() ?? '',
      exercises: exercises,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      favorites: (json['favorites'] as num?)?.toInt() ?? 0,
      shares: (json['shares'] as num?)?.toInt() ?? 0,
      ratingsCount: (json['ratingsCount'] as num?)?.toInt() ?? 0,
      ratingsTotal: (json['ratingsTotal'] as num?)?.toInt() ?? 0,
      isLiked: json['isLiked'] as bool? ?? false,
      isFavorited: json['isFavorited'] as bool? ?? false,
      isSaved: json['isSaved'] as bool? ?? false,
      userRating: (json['userRating'] as num?)?.toInt(),
      comments: comments,
      isFollowingCreator: json['isFollowingCreator'] as bool? ?? false,
    );
  }
}

class PublishCommunityWorkoutInput {
  const PublishCommunityWorkoutInput({
    required this.title,
    required this.description,
    required this.category,
    required this.difficulty,
    required this.tags,
    required this.coverImagePath,
    required this.routine,
  });

  final String title;
  final String description;
  final String category;
  final WorkoutDifficulty difficulty;
  final List<String> tags;
  final String coverImagePath;
  final WorkoutBuilderRoutine routine;
}

class CreatorCommunityStats {
  const CreatorCommunityStats({
    required this.creatorId,
    required this.username,
    required this.profileImagePath,
    required this.totalPublished,
    required this.followers,
    required this.totalDownloads,
    required this.totalShares,
    required this.likesReceived,
    required this.fiveStarRatings,
    required this.badges,
  });

  final String creatorId;
  final String username;
  final String profileImagePath;
  final int totalPublished;
  final int followers;
  final int totalDownloads;
  final int totalShares;
  final int likesReceived;
  final int fiveStarRatings;
  final List<String> badges;
}
