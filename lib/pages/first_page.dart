import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_app/models/workout_models.dart';
import 'package:path_provider/path_provider.dart';
import 'package:my_app/services/reminder_service.dart';
import 'package:my_app/services/settings_service.dart';

class FirstPage extends StatefulWidget {
  const FirstPage({super.key, this.onBackPressed});

  final VoidCallback? onBackPressed;

  @override
  State<FirstPage> createState() => _FirstPageState();
}

class _FirstPageState extends State<FirstPage> {
  final SettingsService _settingsService = SettingsService();
  final ImagePicker _imagePicker = ImagePicker();
  WorkoutInsights _insights = WorkoutInsights.defaults;
  CreatorCommunityStats _communityStats = const CreatorCommunityStats(
    creatorId: 'user.local',
    username: 'Athlete',
    profileImagePath: '',
    totalPublished: 0,
    followers: 0,
    totalDownloads: 0,
    totalShares: 0,
    likesReceived: 0,
    fiveStarRatings: 0,
    badges: [],
  );
  List<WorkoutSessionEntry> _recentSessions = const [];
  int _appLifetimeDays = 1;
  bool _loadingInsights = true;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    try {
      final insights = await _settingsService.loadInsights();
      final sessions = await _settingsService.loadRecentSessions(limit: 30);
      final communityStats = await _settingsService.loadMyCommunityStats();
      final appLifetimeDays = await _settingsService.loadAppLifetimeDays();
      if (!mounted) {
        return;
      }
      setState(() {
        _insights = insights;
        _communityStats = communityStats;
        _recentSessions = sessions;
        _appLifetimeDays = appLifetimeDays;
        _loadingInsights = false;
      });

      try {
        await ReminderService.instance.maybeSendDailyWorkoutReminder(
          _settingsService,
        );
      } catch (_) {
        // Notifications are best-effort and should not interrupt home screen rendering.
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _insights = WorkoutInsights.defaults;
        _communityStats = const CreatorCommunityStats(
          creatorId: 'user.local',
          username: 'Athlete',
          profileImagePath: '',
          totalPublished: 0,
          followers: 0,
          totalDownloads: 0,
          totalShares: 0,
          likesReceived: 0,
          fiveStarRatings: 0,
          badges: [],
        );
        _recentSessions = const [];
        _appLifetimeDays = 1;
        _loadingInsights = false;
      });
    }
  }

  Future<void> _promptForDisplayName() async {
    final controller = TextEditingController(text: _insights.displayName);

    final nextName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A2235),
          title: const Text('Your display name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 24,
            decoration: const InputDecoration(hintText: 'Type your name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (nextName == null) {
      return;
    }

    await _settingsService.saveDisplayName(nextName);
    if (mounted) {
      await _loadInsights();
    }
  }

  Future<void> _showProfilePhotoActions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101A2B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.photo_library_rounded,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Choose profile photo',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _pickProfilePhoto();
                  },
                ),
                if (_insights.profileImagePath.trim().isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFFFB3B3),
                    ),
                    title: const Text(
                      'Remove photo',
                      style: TextStyle(color: Color(0xFFFFD8D8)),
                    ),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await _removeProfilePhoto();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final selected = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        imageQuality: 88,
      );
      if (selected == null) {
        return;
      }

      final persistedPath = await _copyImageToAppStorage(selected.path);
      await _settingsService.saveProfileImagePath(persistedPath);
      if (!mounted) {
        return;
      }
      await _loadInsights();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update profile photo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<String> _copyImageToAppStorage(String sourcePath) async {
    final source = File(sourcePath);
    final appDir = await getApplicationDocumentsDirectory();
    final profileDir = Directory('${appDir.path}/profile');
    if (!await profileDir.exists()) {
      await profileDir.create(recursive: true);
    }
    final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final target = File('${profileDir.path}/$fileName');
    await source.copy(target.path);
    return target.path;
  }

  Future<void> _removeProfilePhoto() async {
    try {
      final existingPath = _insights.profileImagePath.trim();
      await _settingsService.saveProfileImagePath('');
      if (existingPath.isNotEmpty) {
        final existingFile = File(existingPath);
        if (await existingFile.exists()) {
          await existingFile.delete();
        }
      }
      if (!mounted) {
        return;
      }
      await _loadInsights();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove profile photo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final athleteName = _insights.displayName.trim().isEmpty
        ? 'Athlete'
        : _insights.displayName.trim();
    final greeting = 'Hi $athleteName, ready to train?';
    final expandedBadges = _buildBadges(
      _insights,
      _recentSessions,
      _communityStats,
      _appLifetimeDays,
    );

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
          child: Stack(
            children: [
              Positioned(
                top: -40,
                right: -20,
                child: _AuraCircle(
                  size: 170,
                  color: const Color(0xFFFFA69E).withValues(alpha: 0.26),
                ),
              ),
              Positioned(
                bottom: -50,
                left: -30,
                child: _AuraCircle(
                  size: 200,
                  color: const Color(0xFF5EC6FF).withValues(alpha: 0.2),
                ),
              ),
              ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton.filledTonal(
                      onPressed: () {
                        if (widget.onBackPressed != null) {
                          widget.onBackPressed!();
                          return;
                        }
                        Navigator.of(context).maybePop();
                      },
                      icon: const Icon(Icons.arrow_back_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF253454),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ProfileHeroCard(
                    greeting: greeting,
                    onEditName: _promptForDisplayName,
                    onAvatarTap: _showProfilePhotoActions,
                    profileImagePath: _insights.profileImagePath,
                  ),
                  const SizedBox(height: 18),
                  _ProfileHubPanel(
                    insights: _insights,
                    communityStats: _communityStats,
                    sessions: _recentSessions,
                    loading: _loadingInsights,
                    badges: expandedBadges,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_BadgeData> _buildBadges(
    WorkoutInsights insights,
    List<WorkoutSessionEntry> sessions,
    CreatorCommunityStats communityStats,
    int appLifetimeDays,
  ) {
    final totalMinutes = (insights.totalSeconds / 60).round();
    final vo2Sessions = sessions
        .where((entry) => entry.intensity == WorkoutIntensity.high)
        .length;
    final totalCommunityEngagement =
        communityStats.likesReceived + communityStats.totalShares + communityStats.totalDownloads;
    final hasCompletedVo2FourByFour = sessions.any((entry) {
      final fromType = entry.workoutType == 'vo2max_4x4';
      final fromBadge = entry.badgeTitle == 'Completed 4x4 VO2max session';
      final fromIntervals =
          entry.intensity == WorkoutIntensity.high && entry.completedIntervals == 4;
      return fromType || fromBadge || fromIntervals;
    });
    return [
      _BadgeData(
        title: 'Shared First Workout',
        unlocked: communityStats.totalShares >= 1,
        icon: Icons.ios_share_rounded,
      ),
      _BadgeData(
        title: 'Got A Follower',
        unlocked: communityStats.followers >= 1,
        icon: Icons.person_add_alt_1_rounded,
      ),
      _BadgeData(
        title: '100 Followers Club',
        unlocked: communityStats.followers >= 100,
        icon: Icons.groups_rounded,
      ),
      _BadgeData(
        title: 'Doing Great Workouts',
        unlocked: insights.totalWorkouts >= 12 || insights.bestStreakDays >= 10,
        icon: Icons.trending_up_rounded,
      ),
      _BadgeData(
        title: 'Workout Finisher',
        unlocked: insights.totalWorkouts >= 25,
        icon: Icons.check_circle_rounded,
      ),
      _BadgeData(
        title: 'Stayed On App 30 Days',
        unlocked: appLifetimeDays >= 30,
        icon: Icons.calendar_month_rounded,
      ),
      _BadgeData(
        title: 'Completed 4x4 VO2max session',
        unlocked: hasCompletedVo2FourByFour,
        icon: Icons.workspace_premium_rounded,
      ),
      _BadgeData(
        title: 'First Session',
        unlocked: insights.totalWorkouts >= 1,
        icon: Icons.rocket_launch_rounded,
      ),
      _BadgeData(
        title: '5 Workouts',
        unlocked: insights.totalWorkouts >= 5,
        icon: Icons.fitness_center_rounded,
      ),
      _BadgeData(
        title: '7 Day Streak',
        unlocked: insights.bestStreakDays >= 7,
        icon: Icons.local_fire_department_rounded,
      ),
      _BadgeData(
        title: '10 Hours',
        unlocked: totalMinutes >= 600,
        icon: Icons.workspace_premium_rounded,
      ),
      _BadgeData(
        title: 'VO2max Focus',
        unlocked: vo2Sessions >= 2 || insights.totalWorkouts >= 10 || totalCommunityEngagement >= 100,
        icon: Icons.monitor_heart_rounded,
      ),
    ];
  }
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.greeting,
    required this.onEditName,
    required this.onAvatarTap,
    required this.profileImagePath,
  });

  final String greeting;
  final VoidCallback onEditName;
  final VoidCallback onAvatarTap;
  final String profileImagePath;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF384A6A), Color(0xFF2E314A)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2A000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onAvatarTap,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70, width: 2),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8EA1BE), Color(0xFF5A6C86)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: profileImagePath.trim().isEmpty
                        ? const Icon(
                            Icons.person_rounded,
                            size: 44,
                            color: Colors.white,
                          )
                        : Image.file(
                            File(profileImagePath),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) {
                              return const Icon(
                                Icons.person_rounded,
                                size: 44,
                                color: Colors.white,
                              );
                            },
                          ),
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 29,
                  height: 29,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF0A34F),
                    border: Border.all(
                      color: const Color(0xFF1B1E31),
                      width: 2,
                    ),
                  ),
                  child: const Icon(Icons.add_a_photo_rounded, size: 15),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        greeting,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onEditName,
                      icon: const Icon(Icons.edit_rounded, color: Colors.white),
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Stay consistent and stack small wins.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Next up: VO2 Max training.',
                  style: TextStyle(color: Color(0xFFE6E4F4), fontSize: 13.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHubPanel extends StatelessWidget {
  const _ProfileHubPanel({
    required this.insights,
    required this.communityStats,
    required this.sessions,
    required this.loading,
    required this.badges,
  });

  final WorkoutInsights insights;
  final CreatorCommunityStats communityStats;
  final List<WorkoutSessionEntry> sessions;
  final bool loading;
  final List<_BadgeData> badges;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2340).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF445275).withValues(alpha: 0.75),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profile Hub',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Track your progress, streaks, VO2max goals, and milestones in one place.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          _ProgressDeck(
            insights: insights,
            communityStats: communityStats,
            sessions: sessions,
            loading: loading,
          ),
          const SizedBox(height: 14),
          _AchievementsPanel(badges: badges),
          const SizedBox(height: 14),
          _Vo2MaxSpotlight(loading: loading, sessions: sessions),
          const SizedBox(height: 14),
          _Vo2MaxHistoryPanel(loading: loading, sessions: sessions),
        ],
      ),
    );
  }
}

class _ProgressDeck extends StatelessWidget {
  const _ProgressDeck({
    required this.insights,
    required this.communityStats,
    required this.sessions,
    required this.loading,
  });

  final WorkoutInsights insights;
  final CreatorCommunityStats communityStats;
  final List<WorkoutSessionEntry> sessions;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final weeklySessions = sessions
        .where((entry) {
          final now = DateTime.now();
          return now.difference(entry.completedAt).inDays < 7;
        })
        .toList(growable: false);
    final totalMinutes = weeklySessions.fold<int>(0, (sum, entry) {
      return sum + (entry.durationSeconds / 60).round();
    });
    final sessionsThisWeek = weeklySessions.length;
    final weeklyGoalMinutes = 180;
    final goalProgress = (totalMinutes / weeklyGoalMinutes)
        .clamp(0.0, 1.0)
        .toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Weekly progress',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 18),
        if (loading)
          const LinearProgressIndicator(value: 0.35, minHeight: 5)
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: goalProgress,
              minHeight: 5,
              backgroundColor: Colors.white12,
              color: const Color(0xFF9AA5C4),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          loading
              ? 'Loading your progress...'
              : '$totalMinutes / $weeklyGoalMinutes min weekly goal',
          style: const TextStyle(color: Color(0xFFA5ADC6), fontSize: 11),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Workouts',
                value: loading ? '--' : '$sessionsThisWeek',
                delta: 'Completed sessions',
                tone: Color(0xFF5EC6FF),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                label: 'Minutes',
                value: loading ? '--' : '$totalMinutes',
                delta: 'Total training time',
                tone: Color(0xFF86E3A4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                label: 'Best Streak',
                value: loading ? '--' : '${insights.bestStreakDays}',
                delta: 'Consecutive days',
                tone: Color(0xFFFFD37A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Followers',
                value: loading ? '--' : '${communityStats.followers}',
                delta: 'Community followers',
                tone: Color(0xFF9BC4FF),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                label: 'Likes',
                value: loading ? '--' : '${communityStats.likesReceived}',
                delta: 'Likes received',
                tone: Color(0xFFFF9FB3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                label: 'Published',
                value: loading ? '--' : '${communityStats.totalPublished}',
                delta: 'Community workouts',
                tone: Color(0xFFE2B5FF),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.delta,
    required this.tone,
  });

  final String label;
  final String value;
  final String delta;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF202A47).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF445275).withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFFA7B0CA), fontSize: 10.5),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 24,
              height: 1,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            delta,
            style: TextStyle(
              color: tone,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeData {
  const _BadgeData({
    required this.title,
    required this.unlocked,
    required this.icon,
  });

  final String title;
  final bool unlocked;
  final IconData icon;
}

class _AchievementsPanel extends StatelessWidget {
  const _AchievementsPanel({required this.badges});

  final List<_BadgeData> badges;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Achievements',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 9,
          children: badges
              .map((badge) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: badge.unlocked
                        ? const Color(0xFF2D3B56)
                        : const Color(0xFF232C47).withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: badge.unlocked
                          ? const Color(0xFFFFD37A)
                          : Colors.white24,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        badge.icon,
                        size: 15,
                        color: badge.unlocked
                            ? const Color(0xFFFFD37A)
                            : Colors.white54,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        badge.title,
                        style: TextStyle(
                          color: badge.unlocked ? Colors.white : Colors.white60,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _Vo2MaxSpotlight extends StatelessWidget {
  const _Vo2MaxSpotlight({required this.loading, required this.sessions});

  final bool loading;
  final List<WorkoutSessionEntry> sessions;

  @override
  Widget build(BuildContext context) {
    final intenseWeekly = sessions.where((entry) {
      final isFresh = DateTime.now().difference(entry.completedAt).inDays < 7;
      return isFresh && entry.intensity == WorkoutIntensity.high;
    }).length;
    final vo2Progress = (intenseWeekly / 3).clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF27395B), Color(0xFF13233E)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF8CB7FF).withValues(alpha: 0.36),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.monitor_heart_rounded, color: Color(0xFF9BC4FF)),
              SizedBox(width: 8),
              Text(
                'VO2max Focus',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            loading
                ? 'Analyzing your hard-effort sessions...'
                : 'Aim for 3 high-intensity sessions this week to improve aerobic power.',
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: loading ? 0.2 : vo2Progress,
              minHeight: 8,
              backgroundColor: Colors.white12,
              color: const Color(0xFF9BC4FF),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            loading
                ? 'Loading...'
                : '$intenseWeekly / 3 hard sessions this week',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Vo2MaxHistoryPanel extends StatelessWidget {
  const _Vo2MaxHistoryPanel({required this.loading, required this.sessions});

  final bool loading;
  final List<WorkoutSessionEntry> sessions;

  @override
  Widget build(BuildContext context) {
    final vo2Sessions = sessions.where((entry) {
      final fromType = entry.workoutType == 'vo2max_4x4';
      final fromBadge = entry.badgeTitle == 'Completed 4x4 VO2max session';
      final fromIntervals =
          entry.intensity == WorkoutIntensity.high && entry.completedIntervals == 4;
      return fromType || fromBadge || fromIntervals;
    }).toList(growable: false);

    final avgImprovement = vo2Sessions.isEmpty
        ? 0.0
        : vo2Sessions
                .map((entry) => entry.estimatedVo2ImprovementPct ?? 0.0)
                .reduce((a, b) => a + b) /
            vo2Sessions.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2947).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF8CB7FF).withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.insights_rounded, color: Color(0xFF9BC4FF)),
              SizedBox(width: 8),
              Text(
                'VO2max 4x4 History',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            loading
                ? 'Loading completed VO2max sessions...'
                : '${vo2Sessions.length} sessions completed • Avg estimated gain +${avgImprovement.toStringAsFixed(1)}%',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 10),
          if (!loading && vo2Sessions.isEmpty)
            const Text(
              'Complete your first VO2max 4x4 session to start your history.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            )
          else
            Column(
              children: vo2Sessions.take(5).map((entry) {
                final date = '${entry.completedAt.year}-${entry.completedAt.month.toString().padLeft(2, '0')}-${entry.completedAt.day.toString().padLeft(2, '0')}';
                final gain = entry.estimatedVo2ImprovementPct ?? 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: Color(0xFF86E3A4),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$date • ${entry.completedIntervals ?? 4} x 4:00',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      Text(
                        '+${gain.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Color(0xFF9BC4FF),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _AuraCircle extends StatelessWidget {
  const _AuraCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
