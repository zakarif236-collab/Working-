import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_app/controllers/workout_controller.dart';
import 'package:my_app/models/workout_models.dart';
import 'package:my_app/services/cue_service.dart';
import 'package:my_app/services/music_service.dart';
import 'package:my_app/services/settings_service.dart';
import 'package:my_app/widgets/circular_countdown.dart';
import 'package:my_app/widgets/workout_timeline.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:video_player/video_player.dart';

const List<String> _calisthenicsWarmupMoves = [
  'Jumping jacks - 30s',
  'Arm circles - 30s',
  'Leg swings - 30s each leg',
  'High knees - 30s',
];

const List<List<String>> _calisthenicsWarmupAssetKeywords = [
  ['jumping', 'jacks'],
  ['arm', 'circles'],
  ['leg', 'swings'],
  ['high', 'knees'],
];

const List<String> _calisthenicsMainMoves = [
  'Jump squats',
  'Push-ups with shoulder tap',
  'Bear crawl',
  'Mountain climbers',
  'Burpee with push-up',
  'V-ups',
];

const List<String> _calisthenicsCooldownMoves = [
  'Child\'s pose - 20s',
  'Standing quad stretch - 20s each leg',
  'Forward fold - 20s',
];

const List<String> _hiitWorkMoves = [
  'Burpees',
  'Mountain climbers',
  'Jump squats',
  'High knees',
  'Skater jumps',
];

class WorkoutTimerPage extends StatefulWidget {
  const WorkoutTimerPage({super.key});

  @override
  State<WorkoutTimerPage> createState() => _WorkoutTimerPageState();
}

class _WorkoutTimerPageState extends State<WorkoutTimerPage>
    with SingleTickerProviderStateMixin {
  late final WorkoutController _controller;
  late final MusicService _musicService;
  late final CueService _cueService;
  late final SettingsService _settingsService;
  late final AnimationController _pulseController;
  Timer? _settingsPersistDebounce;

  WorkoutIntensity _selectedIntensity = WorkoutConfig.defaults.intensity;
  List<SongModel> _songs = const [];
  bool _loadingSongs = false;
  bool _voiceCueEnabled = true;
  bool _hapticCueEnabled = true;
  bool _muteVoiceWhileMusicPlays = true;
  bool _autoPhaseMusicProfileEnabled = true;
  double _voiceCueVolume = 1.0;
  double _voiceCueRate = 0.52;
  int _lastAnnouncedSeconds = -1;
  int _lastObservedPhaseIndex = -1;
  bool _didAnnounceCompletion = false;
  bool _didRecordCompletionStats = false;
  WorkoutConfig? _launchConfig;
  bool _didReadLaunchConfig = false;
  List<String> _exerciseImageAssets = const [];
  List<String> _exerciseVideoAssets = const [];
  String? _activeExerciseMediaPath;
  VideoPlayerController? _exerciseVideoController;
  bool _loadingExerciseMedia = false;
  bool _showCustomizationPanel = false;

  @override
  void initState() {
    super.initState();
    _controller = WorkoutController();
    _musicService = MusicService();
    _cueService = CueService();
    _settingsService = SettingsService();
    _voiceCueEnabled = _cueService.supportsVoiceCues;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      lowerBound: 0.97,
      upperBound: 1.03,
    );

    _cueService.updateSettings(
      volume: _voiceCueVolume,
      speechRate: _voiceCueRate,
    );
    _initializeFromSavedSettings();
    _loadExerciseMedia();

    _controller.addListener(_watchWorkoutErrors);
  }

  @override
  void dispose() {
    _settingsPersistDebounce?.cancel();
    _controller.removeListener(_watchWorkoutErrors);
    _controller.dispose();
    _pulseController.dispose();
    _disposeExerciseVideoController();
    _cueService.dispose();
    _musicService.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didReadLaunchConfig) {
      return;
    }

    _didReadLaunchConfig = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is WorkoutConfig) {
      _launchConfig = args;
      _controller.updateConfig(args);
      _selectedIntensity = args.intensity;
    }
  }

  void _watchWorkoutErrors() {
    final message = _controller.takeError();
    if (message != null && mounted) {
      _showMessage(message);
    }

    if (_controller.isRunning) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 1;
    }

    _handleWorkoutCues();
    unawaited(_syncCurrentPhaseMedia());
  }

  Future<void> _loadExerciseMedia() async {
    setState(() {
      _loadingExerciseMedia = true;
    });

    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final manifestMap = jsonDecode(manifestContent) as Map<String, dynamic>;

      final imageAssets =
          manifestMap.keys
              .where(
                (path) =>
                    path.startsWith('assets/exercises/images/') &&
                    _isSupportedImageAsset(path),
              )
              .toList()
            ..sort();

      final videoAssets =
          manifestMap.keys
              .where(
                (path) =>
                    path.startsWith('assets/exercises/videos/') &&
                    _isSupportedVideoAsset(path),
              )
              .toList()
            ..sort();

      if (!mounted) {
        return;
      }

      setState(() {
        _exerciseImageAssets = imageAssets;
        _exerciseVideoAssets = videoAssets;
      });

      await _syncCurrentPhaseMedia();
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage(
        'Exercise media not found yet. Add files in assets/exercises/.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingExerciseMedia = false;
        });
      }
    }
  }

  bool _isSupportedImageAsset(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.gif') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  bool _isSupportedVideoAsset(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v');
  }

  int _mediaSeedForPhase(WorkoutPhase phase) {
    final setNumber = phase.setNumber;
    if (setNumber != null && setNumber > 0) {
      return setNumber - 1;
    }
    if (phase.type == WorkoutPhaseType.cooldown) {
      return _controller.config.sets;
    }
    return _controller.phaseIndex.clamp(0, 1 << 20);
  }

  String? _pickMediaAssetForPhase(WorkoutPhase phase) {
    if (phase.type == WorkoutPhaseType.complete) {
      return null;
    }

    if (_isHiitCardio(_controller.config)) {
      final hiitExercise = _currentHiitExercise(phase)?.toLowerCase();
      final keywords = switch (phase.type) {
        WorkoutPhaseType.warmup => <String>['jog'],
        WorkoutPhaseType.work => _hiitKeywordsForExercise(hiitExercise),
        WorkoutPhaseType.rest => <String>['walk'],
        WorkoutPhaseType.cooldown => <String>['stretch'],
        WorkoutPhaseType.complete => <String>[],
      };

      if (keywords.isNotEmpty) {
        final matchingImage = _findAssetByKeywords(_exerciseImageAssets, keywords);
        if (matchingImage != null) {
          return matchingImage;
        }

        final matchingVideo = _findAssetByKeywords(_exerciseVideoAssets, keywords);
        if (matchingVideo != null) {
          return matchingVideo;
        }
      }
    }

    if (_isTabataCardio(_controller.config)) {
      final keywords = switch (phase.type) {
        WorkoutPhaseType.warmup => <String>['jog'],
        WorkoutPhaseType.work => <String>['sprint'],
        WorkoutPhaseType.rest => <String>['pause'],
        WorkoutPhaseType.cooldown => <String>['stretch'],
        WorkoutPhaseType.complete => <String>[],
      };

      if (keywords.isNotEmpty) {
        final matchingImage = _findAssetByKeywords(
          _exerciseImageAssets,
          keywords,
        );
        if (matchingImage != null) {
          return matchingImage;
        }

        final matchingVideo = _findAssetByKeywords(
          _exerciseVideoAssets,
          keywords,
        );
        if (matchingVideo != null) {
          return matchingVideo;
        }
      }
    }

    if (_isVo2MaxFourByFour(_controller.config)) {
      final keywords = switch (phase.type) {
        WorkoutPhaseType.warmup => <String>['run'],
        WorkoutPhaseType.work => <String>['sprint'],
        WorkoutPhaseType.rest => <String>['walk'],
        WorkoutPhaseType.cooldown => <String>['stretch'],
        WorkoutPhaseType.complete => <String>[],
      };

      if (keywords.isNotEmpty) {
        final matchingImage = _findAssetByKeywords(_exerciseImageAssets, keywords);
        if (matchingImage != null) {
          return matchingImage;
        }

        final matchingVideo = _findAssetByKeywords(_exerciseVideoAssets, keywords);
        if (matchingVideo != null) {
          return matchingVideo;
        }
      }
    }

    if (_isCalisthenicsRoutine(_controller.config) &&
        phase.type == WorkoutPhaseType.warmup) {
      final elapsedSeconds =
          (phase.durationSeconds - _controller.remainingSeconds).clamp(
            0,
            phase.durationSeconds,
          );
      final warmupIndex =
          (elapsedSeconds ~/ 30).clamp(0, _calisthenicsWarmupMoves.length - 1);
      final keywords = _calisthenicsWarmupAssetKeywords[warmupIndex];

      final matchingImage = _findAssetByKeywords(_exerciseImageAssets, keywords);
      if (matchingImage != null) {
        return matchingImage;
      }

      final matchingVideo = _findAssetByKeywords(_exerciseVideoAssets, keywords);
      if (matchingVideo != null) {
        return matchingVideo;
      }
    }

    final seed = _mediaSeedForPhase(phase);
    if (_exerciseVideoAssets.isNotEmpty) {
      return _exerciseVideoAssets[seed % _exerciseVideoAssets.length];
    }
    if (_exerciseImageAssets.isNotEmpty) {
      return _exerciseImageAssets[seed % _exerciseImageAssets.length];
    }
    return null;
  }

  String? _findAssetByKeywords(List<String> assets, List<String> keywords) {
    for (final asset in assets) {
      final baseName = _assetBaseName(asset).toLowerCase();
      final hasAllKeywords = keywords.every(baseName.contains);
      if (hasAllKeywords) {
        return asset;
      }
    }
    return null;
  }

  String _assetBaseName(String assetPath) {
    final lastSlash = assetPath.lastIndexOf('/');
    final fileName =
        lastSlash >= 0 ? assetPath.substring(lastSlash + 1) : assetPath;
    final lastDot = fileName.lastIndexOf('.');
    return lastDot > 0 ? fileName.substring(0, lastDot) : fileName;
  }

  Future<void> _syncCurrentPhaseMedia() async {
    if (!mounted) {
      return;
    }

    final selectedPath = _pickMediaAssetForPhase(_controller.currentPhase);
    if (selectedPath == _activeExerciseMediaPath) {
      return;
    }

    _activeExerciseMediaPath = selectedPath;
    if (selectedPath == null) {
      _disposeExerciseVideoController();
      if (mounted) {
        setState(() {});
      }
      return;
    }

    if (_isSupportedVideoAsset(selectedPath)) {
      await _setExerciseVideo(selectedPath);
      return;
    }

    _disposeExerciseVideoController();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _setExerciseVideo(String assetPath) async {
    _disposeExerciseVideoController();
    final controller = VideoPlayerController.asset(assetPath);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _exerciseVideoController = controller;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted) {
        return;
      }

      setState(() {
        _exerciseVideoController = null;
      });
      _showMessage('Could not play this exercise video file.');
    }
  }

  void _disposeExerciseVideoController() {
    final controller = _exerciseVideoController;
    _exerciseVideoController = null;
    controller?.dispose();
  }

  Future<void> _initializeFromSavedSettings() async {
    try {
      final saved = await _settingsService.load();
      if (!mounted) {
        return;
      }

      _controller.updateConfig(saved.config);
      await _cueService.updateSettings(
        volume: saved.voiceCueVolume,
        speechRate: saved.voiceCueRate,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedIntensity = saved.config.intensity;
        _voiceCueEnabled =
            _cueService.supportsVoiceCues && saved.voiceCueEnabled;
        _hapticCueEnabled = saved.hapticCueEnabled;
        _muteVoiceWhileMusicPlays = saved.muteVoiceWhileMusicPlays;
        _voiceCueVolume = saved.voiceCueVolume;
        _voiceCueRate = saved.voiceCueRate;
      });

      if (_launchConfig != null) {
        _controller.updateConfig(_launchConfig!);
        setState(() {
          _selectedIntensity = _launchConfig!.intensity;
        });
        _scheduleSettingsPersist();
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Could not restore your saved settings. Using defaults.');
      }
    }
  }

  void _scheduleSettingsPersist() {
    _settingsPersistDebounce?.cancel();
    _settingsPersistDebounce = Timer(
      const Duration(milliseconds: 300),
      () async {
        try {
          final snapshot = AppSettings(
            config: _controller.config,
            voiceCueEnabled: _voiceCueEnabled,
            hapticCueEnabled: _hapticCueEnabled,
            muteVoiceWhileMusicPlays: _muteVoiceWhileMusicPlays,
            voiceCueVolume: _voiceCueVolume,
            voiceCueRate: _voiceCueRate,
          );
          await _settingsService.save(snapshot);
        } catch (e) {
          if (mounted) {
            _showMessage(
              'Saving settings failed. We will try again on your next change.',
            );
          }
        }
      },
    );
  }

  Future<void> _handleWorkoutCues() async {
    final phaseIndex = _controller.phaseIndex;
    final remaining = _controller.remainingSeconds;
    final canSpeak =
        _voiceCueEnabled &&
        !(_muteVoiceWhileMusicPlays && _musicService.player.playing);

    if (_controller.isRunning && phaseIndex != _lastObservedPhaseIndex) {
      _lastObservedPhaseIndex = phaseIndex;

      await _applyPhaseMusicProfile(_controller.currentPhase);

      if (!_controller.isComplete && phaseIndex < _controller.timeline.length) {
        if (_hapticCueEnabled) {
          await HapticFeedback.mediumImpact();
        }
        // Play phase completion beep (always plays regardless of voice setting)
        await _cueService.playPhaseCompletionBeep();
        if (canSpeak) {
          try {
            await _cueService.announcePhase(
              _phaseVoiceCueText(_controller.currentPhase),
            );
          } on CueServiceException catch (e) {
            _showMessage(e.message);
          }
        }
      }
    }

    if (_controller.isRunning && remaining != _lastAnnouncedSeconds) {
      _lastAnnouncedSeconds = remaining;
      if (remaining > 0 && remaining <= 5) {
        // Stronger haptic feedback for beep effect on 3, 2, 1
        if (remaining <= 3 && _hapticCueEnabled) {
          await HapticFeedback.lightImpact();
        } else if (_hapticCueEnabled) {
          await HapticFeedback.selectionClick();
        }
        // Play voice count if enabled
        try {
          await _cueService.speakCount(remaining, shouldSpeak: canSpeak);
        } on CueServiceException catch (e) {
          _showMessage(e.message);
        }
      }
    }

    if (_controller.isComplete && !_didAnnounceCompletion) {
      _didAnnounceCompletion = true;
      if (!_didRecordCompletionStats) {
        _didRecordCompletionStats = true;
        try {
          await _settingsService.recordWorkoutCompletion(
            _controller.totalWorkoutSeconds,
            config: _controller.config,
          );
          if (mounted && _isVo2MaxFourByFour(_controller.config)) {
            _showMessage(
              'VO2max complete: ${_controller.config.sets} intervals finished. Badge unlocked: Completed 4x4 VO2max session. Estimated VO2max gain +1.2%.',
            );
          }
        } catch (_) {
          // Ignore analytics persistence failures to keep workout UX uninterrupted.
        }
      }
      if (_hapticCueEnabled) {
        await HapticFeedback.heavyImpact();
      }
      // Play completion beep (always plays)
      await _cueService.playWorkoutCompletionBeep();
      if (canSpeak) {
        try {
          await _cueService.announceCompletion();
        } on CueServiceException catch (e) {
          _showMessage(e.message);
        }
      }
      return;
    }

    if (!_controller.isComplete) {
      _didAnnounceCompletion = false;
      _didRecordCompletionStats = false;
    }
  }

  Future<void> _applyPhaseMusicProfile(WorkoutPhase phase) async {
    final profile = _phaseMusicProfile(phase);
    if (!_autoPhaseMusicProfileEnabled || !_musicService.player.playing) {
      return;
    }

    try {
      await _musicService.setPlaybackSpeed(profile.playbackSpeed);
      if (mounted && _musicService.currentSong != null) {
        _showMessage('Music profile: ${profile.label} (${profile.bpmRange})');
      }
    } on MusicServiceException catch (e) {
      _showMessage(e.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _goBackToHome() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    navigator.pushNamedAndRemoveUntil('/', (route) => false);
  }

  void _updateConfig({
    int? sets,
    int? work,
    int? rest,
    int? warmup,
    int? cooldown,
    WorkoutIntensity? intensity,
  }) {
    final next = _controller.config.copyWith(
      sets: sets,
      workSeconds: work,
      restSeconds: rest,
      warmupSeconds: warmup,
      cooldownSeconds: cooldown,
      intensity: intensity,
    );

    _controller.updateConfig(next);
    setState(() {
      _selectedIntensity = next.intensity;
    });
    _didRecordCompletionStats = false;
    _scheduleSettingsPersist();
  }

  Future<void> _openMusicPicker() async {
    setState(() {
      _loadingSongs = true;
    });

    try {
      await _musicService.initialize();
      final songs = await _musicService.loadSongs();
      if (!mounted) {
        return;
      }

      setState(() {
        _songs = songs;
      });

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF111826),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.65,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 54,
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: Colors.white24,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Select Workout Track',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pick a local song from your library',
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _songs.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final song = _songs[index];
                        final selected =
                            _musicService.currentSong?.id == song.id;
                        return ListTile(
                          leading: Icon(
                            selected
                                ? Icons.equalizer_rounded
                                : Icons.music_note_rounded,
                            color: selected
                                ? const Color(0xFF2AB7CA)
                                : Colors.white70,
                          ),
                          title: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            song.artist ?? 'Unknown artist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54),
                          ),
                          onTap: () async {
                            try {
                              await _musicService.playSong(song);
                              if (!context.mounted) {
                                return;
                              }
                              Navigator.pop(context);
                              _showMessage('Now playing: ${song.title}');
                              setState(() {});
                            } on MusicServiceException catch (e) {
                              _showMessage(e.message);
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } on MusicServiceException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) {
        setState(() {
          _loadingSongs = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.currentPhase;
        final palette = _phasePalette(phase.type);

        return Scaffold(
          body: AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette[0], const Color(0xFF0D121C), palette[1]],
                stops: const [0.0, 0.48, 1.0],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -60,
                  left: -40,
                  child: _GlowBlob(
                    color: palette.first.withValues(alpha: 0.55),
                  ),
                ),
                Positioned(
                  bottom: -70,
                  right: -20,
                  child: _GlowBlob(color: palette.last.withValues(alpha: 0.45)),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: IconButton(
                                onPressed: _goBackToHome,
                                icon: const Icon(
                                  Icons.arrow_back_rounded,
                                  color: Colors.white,
                                ),
                                tooltip: 'Back to Home',
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Immersive Workout Timer',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _MusicChip(
                              loading: _loadingSongs,
                              onTap: _openMusicPicker,
                              selectedSongTitle:
                                  _musicService.currentSong?.title,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          children: [
                            _CustomizationToggleCard(
                              expanded: _showCustomizationPanel,
                              onTap: () {
                                setState(() {
                                  _showCustomizationPanel =
                                      !_showCustomizationPanel;
                                });
                              },
                            ),
                            const SizedBox(height: 10),
                            AnimatedCrossFade(
                              duration: const Duration(milliseconds: 220),
                              crossFadeState: _showCustomizationPanel
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              firstChild: const SizedBox.shrink(),
                              secondChild: _ConfigPanel(
                                config: _controller.config,
                                selectedIntensity: _selectedIntensity,
                                onChanged: _updateConfig,
                                voiceCueEnabled: _voiceCueEnabled,
                                hapticCueEnabled: _hapticCueEnabled,
                                onVoiceCueChanged: (value) {
                                  setState(() {
                                    _voiceCueEnabled = value;
                                  });
                                  if (!value) {
                                    _cueService.stop();
                                  }
                                  _scheduleSettingsPersist();
                                },
                                onHapticCueChanged: (value) {
                                  setState(() {
                                    _hapticCueEnabled = value;
                                  });
                                  _scheduleSettingsPersist();
                                },
                                muteVoiceWhileMusicPlays:
                                    _muteVoiceWhileMusicPlays,
                                onMuteVoiceWhileMusicChanged: (value) {
                                  setState(() {
                                    _muteVoiceWhileMusicPlays = value;
                                  });
                                  if (value &&
                                      _musicService.player.playing) {
                                    _cueService.stop();
                                  }
                                  _scheduleSettingsPersist();
                                },
                                voiceCueVolume: _voiceCueVolume,
                                onVoiceCueVolumeChanged: (value) async {
                                  setState(() {
                                    _voiceCueVolume = value;
                                  });
                                  try {
                                    await _cueService.updateSettings(
                                      volume: value,
                                    );
                                  } on CueServiceException catch (e) {
                                    if (mounted) {
                                      _showMessage(e.message);
                                    }
                                  }
                                  _scheduleSettingsPersist();
                                },
                                voiceCueRate: _voiceCueRate,
                                onVoiceCueRateChanged: (value) async {
                                  setState(() {
                                    _voiceCueRate = value;
                                  });
                                  try {
                                    await _cueService.updateSettings(
                                      speechRate: value,
                                    );
                                  } on CueServiceException catch (e) {
                                    if (mounted) {
                                      _showMessage(e.message);
                                    }
                                  }
                                  _scheduleSettingsPersist();
                                },
                              ),
                            ),
                            const SizedBox(height: 14),
                            ScaleTransition(
                              scale: _pulseController,
                              child: CircularCountdown(
                                progress: _controller.phaseProgress,
                                seconds: _controller.remainingSeconds,
                                label: _phaseClockLabel(phase),
                                gradient: [palette.first, palette.last],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _ExerciseMediaPanel(
                              mediaPath: _activeExerciseMediaPath,
                              videoController: _exerciseVideoController,
                              loading: _loadingExerciseMedia,
                            ),
                            const SizedBox(height: 12),
                            _ProgressHeader(
                              progress: _controller.totalProgress,
                              elapsed: _controller.elapsedWorkoutSeconds,
                              total: _controller.totalWorkoutSeconds,
                            ),
                            const SizedBox(height: 10),
                            _PhaseTempoPanel(
                              profile: _phaseMusicProfile(phase),
                              autoProfileEnabled: _autoPhaseMusicProfileEnabled,
                              isMusicPlaying: _musicService.player.playing,
                              playbackSpeed: _musicService.playbackSpeed,
                              onAutoProfileChanged: (value) async {
                                setState(() {
                                  _autoPhaseMusicProfileEnabled = value;
                                });
                                if (value && _musicService.player.playing) {
                                  await _applyPhaseMusicProfile(phase);
                                }
                              },
                            ),
                            const SizedBox(height: 10),
                            WorkoutTimeline(
                              timeline: _controller.timeline,
                              currentIndex: _controller.phaseIndex,
                              currentRemainingSeconds:
                                  _controller.remainingSeconds,
                              program: _controller.config.program,
                            ),
                            if (_isHiitCardio(_controller.config)) ...[
                              const SizedBox(height: 14),
                              const _HiitGuideCard(),
                            ],
                            if (_isVo2MaxFourByFour(_controller.config)) ...[
                              const SizedBox(height: 14),
                              const _Vo2MaxGuideCard(),
                            ],
                            if (_isTabataCardio(_controller.config)) ...[
                              const SizedBox(height: 14),
                              const _TabataGuideCard(),
                            ],
                            if (_isCalisthenicsRoutine(_controller.config)) ...[
                              const SizedBox(height: 14),
                              _CalisthenicsGuideCard(
                                phase: phase,
                                currentExercise: _currentCalisthenicsExercise(
                                  phase,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            _ActionControls(
                              running: _controller.isRunning,
                              complete: _controller.isComplete,
                              onStartPause: () {
                                if (_controller.isRunning) {
                                  _controller.pause();
                                } else {
                                  _controller.start();
                                }
                              },
                              onReset: () {
                                _didRecordCompletionStats = false;
                                _controller.stop(reset: true);
                              },
                              onSkip: _controller.skipPhase,
                              onMusicToggle: () async {
                                try {
                                  await _musicService.togglePlayPause();
                                  if (_musicService.player.playing) {
                                    await _applyPhaseMusicProfile(phase);
                                  }
                                  if (_muteVoiceWhileMusicPlays &&
                                      _musicService.player.playing) {
                                    await _cueService.stop();
                                  }
                                  if (mounted) {
                                    setState(() {});
                                  }
                                } on MusicServiceException catch (e) {
                                  _showMessage(e.message);
                                }
                              },
                              isMusicPlaying: _musicService.player.playing,
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Color> _phasePalette(WorkoutPhaseType type) {
    if (_isHiitCardio(_controller.config)) {
      switch (type) {
        case WorkoutPhaseType.warmup:
        case WorkoutPhaseType.cooldown:
          return const [Color(0xFF6BCB77), Color(0xFF3FA34D)];
        case WorkoutPhaseType.work:
          return const [Color(0xFFFF5A5F), Color(0xFFD7263D)];
        case WorkoutPhaseType.rest:
          return const [Color(0xFF2AB7CA), Color(0xFF1C7C8C)];
        case WorkoutPhaseType.complete:
          return const [Color(0xFF8E9AAF), Color(0xFF3C465F)];
      }
    }

    if (_isTabataCardio(_controller.config)) {
      switch (type) {
        case WorkoutPhaseType.warmup:
        case WorkoutPhaseType.cooldown:
          return const [Color(0xFF6BCB77), Color(0xFF3FA34D)];
        case WorkoutPhaseType.work:
          return const [Color(0xFFFF5A5F), Color(0xFFD7263D)];
        case WorkoutPhaseType.rest:
          return const [Color(0xFF2AB7CA), Color(0xFF1C7C8C)];
        case WorkoutPhaseType.complete:
          return const [Color(0xFF8E9AAF), Color(0xFF3C465F)];
      }
    }

    if (_isVo2MaxFourByFour(_controller.config)) {
      switch (type) {
        case WorkoutPhaseType.warmup:
        case WorkoutPhaseType.cooldown:
          return const [Color(0xFF6BCB77), Color(0xFF3FA34D)];
        case WorkoutPhaseType.work:
          return const [Color(0xFFFF5A5F), Color(0xFFD7263D)];
        case WorkoutPhaseType.rest:
          return const [Color(0xFF2AB7CA), Color(0xFF1C7C8C)];
        case WorkoutPhaseType.complete:
          return const [Color(0xFF8E9AAF), Color(0xFF3C465F)];
      }
    }

    switch (type) {
      case WorkoutPhaseType.warmup:
        return const [Color(0xFFF7A531), Color(0xFFE65C00)];
      case WorkoutPhaseType.work:
        return const [Color(0xFFFF5A5F), Color(0xFFD7263D)];
      case WorkoutPhaseType.rest:
        return const [Color(0xFF2AB7CA), Color(0xFF1C7C8C)];
      case WorkoutPhaseType.cooldown:
        return const [Color(0xFF6BCB77), Color(0xFF3FA34D)];
      case WorkoutPhaseType.complete:
        return const [Color(0xFF8E9AAF), Color(0xFF3C465F)];
    }
  }

  String _phaseLabel(WorkoutPhase phase) {
    if (phase.type == WorkoutPhaseType.complete) {
      return 'Session Complete';
    }
    if (phase.setNumber != null && phase.type == WorkoutPhaseType.work) {
      return '${phase.label} • Set ${phase.setNumber}';
    }
    return phase.label;
  }

  String _phaseClockLabel(WorkoutPhase phase) {
    if (phase.type == WorkoutPhaseType.complete) {
      return 'Session Complete';
    }

    if (_isHiitCardio(_controller.config)) {
      switch (phase.type) {
        case WorkoutPhaseType.warmup:
          return 'March, jacks, and easy high knees';
        case WorkoutPhaseType.work:
          return _currentHiitExercise(phase) ?? 'HIIT Work';
        case WorkoutPhaseType.rest:
          return 'Walk in place and deep breathing';
        case WorkoutPhaseType.cooldown:
          return 'Walk slowly and stretch legs and hips';
        case WorkoutPhaseType.complete:
          return 'Session Complete';
      }
    }

    if (_isTabataCardio(_controller.config)) {
      switch (phase.type) {
        case WorkoutPhaseType.warmup:
          return 'Easy jog or dynamic moves';
        case WorkoutPhaseType.work:
          return 'All-out effort';
        case WorkoutPhaseType.rest:
          return 'Passive or light movement';
        case WorkoutPhaseType.cooldown:
          return 'Stretching and slow walk';
        case WorkoutPhaseType.complete:
          return 'Session Complete';
      }
    }

    if (_isVo2MaxFourByFour(_controller.config)) {
      switch (phase.type) {
        case WorkoutPhaseType.warmup:
          return 'Easy pace with light cardio and dynamic stretches';
        case WorkoutPhaseType.work:
          return 'Push hard';
        case WorkoutPhaseType.rest:
          return 'Recover';
        case WorkoutPhaseType.cooldown:
          return 'Stretch and bring heart rate down';
        case WorkoutPhaseType.complete:
          return 'Session Complete';
      }
    }

    return _phaseLabel(phase);
  }

  String _phaseVoiceCueText(WorkoutPhase phase) {
    if (_isHiitCardio(_controller.config)) {
      switch (phase.type) {
        case WorkoutPhaseType.warmup:
          return 'Warm-up: march, jumping jacks, and easy high knees.';
        case WorkoutPhaseType.work:
          final exercise = _currentHiitExercise(phase);
          return exercise == null
              ? 'Work phase. Push hard.'
              : 'Work phase. $exercise.';
        case WorkoutPhaseType.rest:
          return 'Rest phase. Walk in place and breathe deeply.';
        case WorkoutPhaseType.cooldown:
          return 'Cool down. Walk slowly, then stretch legs and hips.';
        case WorkoutPhaseType.complete:
          return 'Session Complete';
      }
    }

    if (_isTabataCardio(_controller.config)) {
      switch (phase.type) {
        case WorkoutPhaseType.warmup:
          return 'Warm-up. Easy jog and dynamic moves.';
        case WorkoutPhaseType.work:
          return 'Go hard!';
        case WorkoutPhaseType.rest:
          return 'Rest now.';
        case WorkoutPhaseType.cooldown:
          return 'Cool down with stretching and slow walk.';
        case WorkoutPhaseType.complete:
          return 'Session Complete';
      }
    }

    if (_isCalisthenicsRoutine(_controller.config)) {
      switch (phase.type) {
        case WorkoutPhaseType.warmup:
          return 'Warm-up: jumping jacks, arm circles, leg swings, high knees.';
        case WorkoutPhaseType.work:
          final exercise = _currentCalisthenicsExercise(phase);
          return exercise == null
              ? _phaseLabel(phase)
              : '$exercise. Stay sharp.';
        case WorkoutPhaseType.rest:
          final nextExercise = _nextCalisthenicsExercise(phase);
          return nextExercise == null
              ? 'Reset and breathe.'
              : 'Reset. Next up: $nextExercise.';
        case WorkoutPhaseType.cooldown:
          return 'Cool down: child\'s pose, quad stretch, forward fold.';
        case WorkoutPhaseType.complete:
          return 'Session Complete';
      }
    }

    if (!_isVo2MaxFourByFour(_controller.config)) {
      return _phaseLabel(phase);
    }

    switch (phase.type) {
      case WorkoutPhaseType.warmup:
        return 'Warm-up. Keep it light.';
      case WorkoutPhaseType.work:
        final index = phase.setNumber ?? 1;
        return 'Interval $index starts - push hard!';
      case WorkoutPhaseType.rest:
        return 'Recover now.';
      case WorkoutPhaseType.cooldown:
        return 'Cool down. Great job.';
      case WorkoutPhaseType.complete:
        return 'Session Complete';
    }
  }

  bool _isVo2MaxFourByFour(WorkoutConfig config) {
    return config.program == WorkoutProgram.vo2max ||
        (config.sets == 4 &&
            config.workSeconds == 240 &&
            config.restSeconds == 180 &&
            config.warmupSeconds == 600 &&
            config.cooldownSeconds >= 300);
  }

  bool _isHiitCardio(WorkoutConfig config) {
    return config.program == WorkoutProgram.hiitCardio ||
        (config.sets == 5 &&
            config.workSeconds == 40 &&
            config.restSeconds == 20 &&
            config.warmupSeconds == 180 &&
            config.cooldownSeconds == 120);
  }

  bool _isTabataCardio(WorkoutConfig config) {
    return config.program == WorkoutProgram.tabataCardio ||
        (config.sets == 8 &&
            config.workSeconds == 20 &&
            config.restSeconds == 10 &&
            config.warmupSeconds >= 120 &&
            config.warmupSeconds <= 180 &&
            config.cooldownSeconds >= 120 &&
            config.cooldownSeconds <= 180);
  }

  bool _isCalisthenicsRoutine(WorkoutConfig config) {
    return config.program == WorkoutProgram.calisthenics ||
        (config.sets == 12 &&
            config.workSeconds == 40 &&
            config.restSeconds == 20 &&
            config.warmupSeconds == 120 &&
            config.cooldownSeconds == 60 &&
            config.finalRestSeconds == 20);
  }

  String? _currentHiitExercise(WorkoutPhase phase) {
    if (phase.type != WorkoutPhaseType.work || phase.setNumber == null) {
      return null;
    }
    return _hiitWorkMoves[(phase.setNumber! - 1) % _hiitWorkMoves.length];
  }

  List<String> _hiitKeywordsForExercise(String? exercise) {
    if (exercise == null) {
      return const <String>['burpee'];
    }
    if (exercise.contains('mountain')) {
      return const <String>['mountain', 'climber'];
    }
    if (exercise.contains('squat')) {
      return const <String>['squat'];
    }
    if (exercise.contains('high knees')) {
      return const <String>['high', 'knees'];
    }
    if (exercise.contains('skater')) {
      return const <String>['skater'];
    }
    return const <String>['burpee'];
  }

  String? _currentCalisthenicsExercise(WorkoutPhase phase) {
    if (phase.type != WorkoutPhaseType.work || phase.setNumber == null) {
      return null;
    }
    return _calisthenicsMainMoves[(phase.setNumber! - 1) %
        _calisthenicsMainMoves.length];
  }

  String? _nextCalisthenicsExercise(WorkoutPhase phase) {
    final currentSet = phase.setNumber;
    if (currentSet == null || currentSet >= _controller.config.sets) {
      return null;
    }
    return _calisthenicsMainMoves[currentSet % _calisthenicsMainMoves.length];
  }

  _PhaseMusicProfile _phaseMusicProfile(WorkoutPhase phase) {
    if (_isHiitCardio(_controller.config)) {
      switch (phase.type) {
        case WorkoutPhaseType.warmup:
          return const _PhaseMusicProfile(
            label: 'Warm-up',
            bpmRange: '100-115 BPM',
            playbackSpeed: 0.95,
          );
        case WorkoutPhaseType.work:
          return const _PhaseMusicProfile(
            label: 'HIIT Work',
            bpmRange: '130-155 BPM',
            playbackSpeed: 1.12,
          );
        case WorkoutPhaseType.rest:
          return const _PhaseMusicProfile(
            label: 'HIIT Rest',
            bpmRange: '90-105 BPM',
            playbackSpeed: 0.9,
          );
        case WorkoutPhaseType.cooldown:
          return const _PhaseMusicProfile(
            label: 'Cool-down',
            bpmRange: '75-90 BPM',
            playbackSpeed: 0.85,
          );
        case WorkoutPhaseType.complete:
          return const _PhaseMusicProfile(
            label: 'Complete',
            bpmRange: '75-90 BPM',
            playbackSpeed: 0.85,
          );
      }
    }

    if (_isTabataCardio(_controller.config)) {
      switch (phase.type) {
        case WorkoutPhaseType.warmup:
          return const _PhaseMusicProfile(
            label: 'Warm-up',
            bpmRange: '100-115 BPM',
            playbackSpeed: 0.95,
          );
        case WorkoutPhaseType.work:
          return const _PhaseMusicProfile(
            label: 'Tabata Work',
            bpmRange: '140-165 BPM',
            playbackSpeed: 1.2,
          );
        case WorkoutPhaseType.rest:
          return const _PhaseMusicProfile(
            label: 'Tabata Rest',
            bpmRange: '90-105 BPM',
            playbackSpeed: 0.9,
          );
        case WorkoutPhaseType.cooldown:
          return const _PhaseMusicProfile(
            label: 'Cool-down',
            bpmRange: '75-90 BPM',
            playbackSpeed: 0.85,
          );
        case WorkoutPhaseType.complete:
          return const _PhaseMusicProfile(
            label: 'Complete',
            bpmRange: '75-90 BPM',
            playbackSpeed: 0.85,
          );
      }
    }

    if (_isVo2MaxFourByFour(_controller.config)) {
      switch (phase.type) {
        case WorkoutPhaseType.warmup:
          return const _PhaseMusicProfile(
            label: 'Warm-up',
            bpmRange: '90-100 BPM',
            playbackSpeed: 0.9,
          );
        case WorkoutPhaseType.work:
          return const _PhaseMusicProfile(
            label: 'High Intensity',
            bpmRange: '130-150 BPM',
            playbackSpeed: 1.15,
          );
        case WorkoutPhaseType.rest:
          return const _PhaseMusicProfile(
            label: 'Recovery',
            bpmRange: '90-100 BPM',
            playbackSpeed: 0.9,
          );
        case WorkoutPhaseType.cooldown:
          return const _PhaseMusicProfile(
            label: 'Cool-down',
            bpmRange: '70-80 BPM',
            playbackSpeed: 0.8,
          );
        case WorkoutPhaseType.complete:
          return const _PhaseMusicProfile(
            label: 'Complete',
            bpmRange: '70-80 BPM',
            playbackSpeed: 0.8,
          );
      }
    }

    switch (phase.type) {
      case WorkoutPhaseType.warmup:
        return const _PhaseMusicProfile(
          label: 'Warm-up',
          bpmRange: '100-115 BPM',
          playbackSpeed: 0.95,
        );
      case WorkoutPhaseType.work:
        return const _PhaseMusicProfile(
          label: 'Work',
          bpmRange: '120-140 BPM',
          playbackSpeed: 1.05,
        );
      case WorkoutPhaseType.rest:
        return const _PhaseMusicProfile(
          label: 'Rest',
          bpmRange: '90-105 BPM',
          playbackSpeed: 0.9,
        );
      case WorkoutPhaseType.cooldown:
        return const _PhaseMusicProfile(
          label: 'Cool-down',
          bpmRange: '75-90 BPM',
          playbackSpeed: 0.85,
        );
      case WorkoutPhaseType.complete:
        return const _PhaseMusicProfile(
          label: 'Complete',
          bpmRange: '75-90 BPM',
          playbackSpeed: 0.85,
        );
    }
  }
}

class _PhaseMusicProfile {
  const _PhaseMusicProfile({
    required this.label,
    required this.bpmRange,
    required this.playbackSpeed,
  });

  final String label;
  final String bpmRange;
  final double playbackSpeed;
}

class _ExerciseMediaPanel extends StatelessWidget {
  const _ExerciseMediaPanel({
    required this.mediaPath,
    required this.videoController,
    required this.loading,
  });

  final String? mediaPath;
  final VideoPlayerController? videoController;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final hasMedia = mediaPath != null;
    final isVideo =
        hasMedia && mediaPath!.startsWith('assets/exercises/videos/');

    Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (!hasMedia) {
      body = const Center(
        child: Text(
          'Add GIF/MP4 files to assets/exercises to see exercise visuals here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      );
    } else if (isVideo) {
      if (videoController != null && videoController!.value.isInitialized) {
        final ratio = videoController!.value.aspectRatio <= 0
            ? 16 / 9
            : videoController!.value.aspectRatio;
        body = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: ratio,
            child: VideoPlayer(videoController!),
          ),
        );
      } else {
        body = const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
    } else {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          mediaPath!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Text(
                'Could not load this exercise image.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          },
        ),
      );
    }

    return Container(
      height: 200,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: body,
    );
  }
}

class _CalisthenicsGuideCard extends StatelessWidget {
  const _CalisthenicsGuideCard({
    required this.phase,
    required this.currentExercise,
  });

  final WorkoutPhase phase;
  final String? currentExercise;

  @override
  Widget build(BuildContext context) {
    final focusText = switch (phase.type) {
      WorkoutPhaseType.warmup =>
        'Warm-up flow: wake up joints, raise heart rate, stay light.',
      WorkoutPhaseType.work =>
        currentExercise == null
            ? 'Main circuit: 40s work, 20s rest.'
            : 'Current focus: $currentExercise for 40 seconds.',
      WorkoutPhaseType.rest =>
        'Use the 20-second reset to control breathing and set up the next move.',
      WorkoutPhaseType.cooldown =>
        'Slow everything down and let the heart rate come back under control.',
      WorkoutPhaseType.complete => 'Routine complete. Walk it off and recover.',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '15-Min Calisthenics',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '2 min warm-up, 12 min circuit, 1 min cool-down',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Text(
            focusText,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const _GuideSection(
            title: 'Warm-up',
            items: _calisthenicsWarmupMoves,
          ),
          const SizedBox(height: 10),
          const _GuideSection(
            title: 'Main Circuit',
            items: _calisthenicsMainMoves,
          ),
          const SizedBox(height: 10),
          const _GuideSection(
            title: 'Cool-down',
            items: _calisthenicsCooldownMoves,
          ),
        ],
      ),
    );
  }
}

class _Vo2MaxGuideCard extends StatelessWidget {
  const _Vo2MaxGuideCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'VO2max 4x4 Structure',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Total session time: about 40-45 minutes',
            style: TextStyle(color: Colors.white70),
          ),
          SizedBox(height: 12),
          _Vo2PhaseRow(
            icon: Icons.directions_run_rounded,
            phase: 'Follow-up',
            duration: '10 min',
            intensity: '60-70% HRmax',
            cue: 'Easy pace with light cardio and dynamic stretches',
          ),
          _Vo2PhaseRow(
            icon: Icons.bolt_rounded,
            phase: 'Interval 1',
            duration: '4 min',
            intensity: '85-95% HRmax',
            cue: 'Push hard',
          ),
          _Vo2PhaseRow(
            icon: Icons.directions_walk_rounded,
            phase: 'Follow-up 1',
            duration: '3 min',
            intensity: 'Easy pace',
            cue: 'Recover',
          ),
          _Vo2PhaseRow(
            icon: Icons.bolt_rounded,
            phase: 'Interval 2',
            duration: '4 min',
            intensity: '85-95% HRmax',
            cue: 'Push hard',
          ),
          _Vo2PhaseRow(
            icon: Icons.directions_walk_rounded,
            phase: 'Follow-up 2',
            duration: '3 min',
            intensity: 'Easy pace',
            cue: 'Recover',
          ),
          _Vo2PhaseRow(
            icon: Icons.bolt_rounded,
            phase: 'Interval 3',
            duration: '4 min',
            intensity: '85-95% HRmax',
            cue: 'Push hard',
          ),
          _Vo2PhaseRow(
            icon: Icons.directions_walk_rounded,
            phase: 'Follow-up 3',
            duration: '3 min',
            intensity: 'Easy pace',
            cue: 'Recover',
          ),
          _Vo2PhaseRow(
            icon: Icons.bolt_rounded,
            phase: 'Interval 4',
            duration: '4 min',
            intensity: '85-95% HRmax',
            cue: 'Push hard',
          ),
          _Vo2PhaseRow(
            icon: Icons.directions_walk_rounded,
            phase: 'Follow-up 4',
            duration: '3 min',
            intensity: 'Easy pace',
            cue: 'Recover',
          ),
          _Vo2PhaseRow(
            icon: Icons.self_improvement_rounded,
            phase: 'Cool-down',
            duration: '5-10 min',
            intensity: 'Around 60% HRmax',
            cue: 'Stretch and bring heart rate down',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _HiitGuideCard extends StatelessWidget {
  const _HiitGuideCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'HIIT Cardio Protocol',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Duration: 15 minutes',
            style: TextStyle(color: Colors.white70),
          ),
          SizedBox(height: 12),
          _Vo2PhaseRow(
            icon: Icons.directions_walk_rounded,
            phase: 'Warm-up',
            duration: '3 min',
            intensity: 'Easy pace',
            cue: 'March in place, jumping jacks, high knees (easy)',
          ),
          _Vo2PhaseRow(
            icon: Icons.bolt_rounded,
            phase: 'Work',
            duration: '40 sec',
            intensity: 'Intermediate',
            cue: 'Burpees, climbers, jump squats, high knees, or skater jumps',
          ),
          _Vo2PhaseRow(
            icon: Icons.pause_circle_rounded,
            phase: 'Rest',
            duration: '20 sec',
            intensity: 'Recovery',
            cue: 'Walk in place and deep breathing',
          ),
          _Vo2PhaseRow(
            icon: Icons.repeat_rounded,
            phase: 'Repeat cycle',
            duration: '5 rounds (10 min)',
            intensity: 'Cardio and endurance focus',
            cue: 'Display one move each round or let user choose',
          ),
          _Vo2PhaseRow(
            icon: Icons.self_improvement_rounded,
            phase: 'Cool-down',
            duration: '2 min',
            intensity: 'Easy',
            cue: 'Walk slowly and stretch legs and hips',
            isLast: true,
          ),
          SizedBox(height: 10),
          _GuideSection(title: 'Work Moves', items: _hiitWorkMoves),
          SizedBox(height: 10),
          Text(
            'Estimated calories: 120-220 kcal (depends on body weight and intensity)',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TabataGuideCard extends StatelessWidget {
  const _TabataGuideCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Tabata Cardio Protocol',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Total session time: about 10 minutes',
            style: TextStyle(color: Colors.white70),
          ),
          SizedBox(height: 12),
          _Vo2PhaseRow(
            icon: Icons.directions_run_rounded,
            phase: 'Warm-up',
            duration: '2-3 min',
            intensity: 'Easy jog or dynamic moves',
            cue: 'Jogging icon or light cardio GIF',
          ),
          _Vo2PhaseRow(
            icon: Icons.bolt_rounded,
            phase: 'Work interval',
            duration: '20 sec',
            intensity: 'All-out effort',
            cue: 'Red block + sprint icon (Go hard!)',
          ),
          _Vo2PhaseRow(
            icon: Icons.pause_circle_rounded,
            phase: 'Rest interval',
            duration: '10 sec',
            intensity: 'Passive or light movement',
            cue: 'Blue block + pause icon (Rest now.)',
          ),
          _Vo2PhaseRow(
            icon: Icons.repeat_rounded,
            phase: 'Repeat cycle',
            duration: '8 rounds (4 min total)',
            intensity: 'Alternating work and rest',
            cue: 'Timeline alternates red and blue blocks',
          ),
          _Vo2PhaseRow(
            icon: Icons.self_improvement_rounded,
            phase: 'Cool-down',
            duration: '2-3 min',
            intensity: 'Stretching and slow walk',
            cue: 'Stretch icon or yoga GIF',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _Vo2PhaseRow extends StatelessWidget {
  const _Vo2PhaseRow({
    required this.icon,
    required this.phase,
    required this.duration,
    required this.intensity,
    required this.cue,
    this.isLast = false,
  });

  final IconData icon;
  final String phase;
  final String duration;
  final String intensity;
  final String cue;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$phase • $duration',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  intensity,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  cue,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map(
                (item) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    item,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _CustomizationToggleCard extends StatelessWidget {
  const _CustomizationToggleCard({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Customize Timing',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: Icon(
              expanded ? Icons.expand_less_rounded : Icons.edit_rounded,
              size: 18,
            ),
            label: Text(expanded ? 'Close' : 'Customize Timing'),
          ),
        ],
      ),
    );
  }
}

class _ConfigPanel extends StatelessWidget {
  const _ConfigPanel({
    required this.config,
    required this.selectedIntensity,
    required this.onChanged,
    required this.voiceCueEnabled,
    required this.hapticCueEnabled,
    required this.onVoiceCueChanged,
    required this.onHapticCueChanged,
    required this.muteVoiceWhileMusicPlays,
    required this.onMuteVoiceWhileMusicChanged,
    required this.voiceCueVolume,
    required this.onVoiceCueVolumeChanged,
    required this.voiceCueRate,
    required this.onVoiceCueRateChanged,
  });

  final WorkoutConfig config;
  final WorkoutIntensity selectedIntensity;
  final void Function({
    int? sets,
    int? work,
    int? rest,
    int? warmup,
    int? cooldown,
    WorkoutIntensity? intensity,
  })
  onChanged;
  final bool voiceCueEnabled;
  final bool hapticCueEnabled;
  final ValueChanged<bool> onVoiceCueChanged;
  final ValueChanged<bool> onHapticCueChanged;
  final bool muteVoiceWhileMusicPlays;
  final ValueChanged<bool> onMuteVoiceWhileMusicChanged;
  final double voiceCueVolume;
  final ValueChanged<double> onVoiceCueVolumeChanged;
  final double voiceCueRate;
  final ValueChanged<double> onVoiceCueRateChanged;

  @override
  Widget build(BuildContext context) {
    const double setsMax = 50.0;
    final double workMax = config.workSeconds > 240
        ? config.workSeconds.toDouble()
        : 240.0;
    final double restMax = config.restSeconds > 180
        ? config.restSeconds.toDouble()
        : 180.0;
    final double warmupMax = config.warmupSeconds > 600
        ? config.warmupSeconds.toDouble()
        : 600.0;
    final double cooldownMax = config.cooldownSeconds > 300
        ? config.cooldownSeconds.toDouble()
        : 300.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Session Builder',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          _LabeledSlider(
            label: 'Sets: ${config.sets}',
            value: config.sets.toDouble(),
            min: 1,
            max: setsMax,
            divisions: setsMax.round() - 1,
            onChanged: (v) => onChanged(sets: v.round()),
          ),
          _LabeledSlider(
            label: 'Work: ${config.workSeconds}s',
            value: config.workSeconds.toDouble(),
            min: 10,
            max: workMax,
            divisions: ((workMax - 10) / 5).round(),
            onChanged: (v) => onChanged(work: v.round()),
          ),
          _LabeledSlider(
            label: 'Rest: ${config.restSeconds}s',
            value: config.restSeconds.toDouble(),
            min: 5,
            max: restMax,
            divisions: ((restMax - 5) / 5).round(),
            onChanged: (v) => onChanged(rest: v.round()),
          ),
          _LabeledSlider(
            label: 'Warmup: ${config.warmupSeconds}s',
            value: config.warmupSeconds.toDouble(),
            min: 0,
            max: warmupMax,
            divisions: (warmupMax / 5).round(),
            onChanged: (v) => onChanged(warmup: v.round()),
          ),
          _LabeledSlider(
            label: 'Cooldown: ${config.cooldownSeconds}s',
            value: config.cooldownSeconds.toDouble(),
            min: 0,
            max: cooldownMax,
            divisions: (cooldownMax / 5).round(),
            onChanged: (v) => onChanged(cooldown: v.round()),
          ),
          const SizedBox(height: 6),
          const Text('Intensity', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: WorkoutIntensity.values.map((intensity) {
              final selected = intensity == selectedIntensity;
              return ChoiceChip(
                label: Text(
                  intensity.name.toUpperCase(),
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                selected: selected,
                onSelected: (_) => onChanged(intensity: intensity),
                selectedColor: Colors.white,
                backgroundColor: Colors.white12,
                side: const BorderSide(color: Colors.white24),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CueToggleTile(
                  label: 'Voice Cue',
                  value: voiceCueEnabled,
                  icon: Icons.record_voice_over_rounded,
                  onChanged: onVoiceCueChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CueToggleTile(
                  label: 'Haptic Cue',
                  value: hapticCueEnabled,
                  icon: Icons.vibration_rounded,
                  onChanged: onHapticCueChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _CueToggleTile(
            label: 'Mute Voice While Music Plays',
            value: muteVoiceWhileMusicPlays,
            icon: Icons.volume_off_rounded,
            onChanged: onMuteVoiceWhileMusicChanged,
          ),
          const SizedBox(height: 10),
          _LabeledSlider(
            label: 'Voice Volume: ${(voiceCueVolume * 100).round()}%',
            value: voiceCueVolume,
            min: 0,
            max: 1,
            divisions: 10,
            onChanged: onVoiceCueVolumeChanged,
          ),
          _LabeledSlider(
            label: 'Voice Speed: ${voiceCueRate.toStringAsFixed(2)}x',
            value: voiceCueRate,
            min: 0.2,
            max: 0.8,
            divisions: 12,
            onChanged: onVoiceCueRateChanged,
          ),
        ],
      ),
    );
  }
}

class _CueToggleTile extends StatelessWidget {
  const _CueToggleTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final IconData icon;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(min, max).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        Slider(
          value: safeValue,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.progress,
    required this.elapsed,
    required this.total,
  });

  final double progress;
  final int elapsed;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Workout Progress',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: Colors.white12,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_formatSeconds(elapsed)} / ${_formatSeconds(total)}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSeconds(int value) {
    final m = value ~/ 60;
    final s = value % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _ActionControls extends StatelessWidget {
  const _ActionControls({
    required this.running,
    required this.complete,
    required this.onStartPause,
    required this.onReset,
    required this.onSkip,
    required this.onMusicToggle,
    required this.isMusicPlaying,
  });

  final bool running;
  final bool complete;
  final VoidCallback onStartPause;
  final VoidCallback onReset;
  final VoidCallback onSkip;
  final VoidCallback onMusicToggle;
  final bool isMusicPlaying;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: onStartPause,
          icon: Icon(running ? Icons.pause_circle : Icons.play_arrow_rounded),
          label: Text(
            running
                ? 'Pause'
                : complete
                ? 'Restart'
                : 'Start',
          ),
        ),
        OutlinedButton.icon(
          onPressed: onSkip,
          icon: const Icon(Icons.skip_next_rounded),
          label: const Text('Skip'),
        ),
        OutlinedButton.icon(
          onPressed: onReset,
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Reset'),
        ),
        OutlinedButton.icon(
          onPressed: onMusicToggle,
          icon: Icon(
            isMusicPlaying ? Icons.music_off_rounded : Icons.music_note_rounded,
          ),
          label: Text(isMusicPlaying ? 'Pause Music' : 'Play Music'),
        ),
      ],
    );
  }
}

class _PhaseTempoPanel extends StatelessWidget {
  const _PhaseTempoPanel({
    required this.profile,
    required this.autoProfileEnabled,
    required this.isMusicPlaying,
    required this.playbackSpeed,
    required this.onAutoProfileChanged,
  });

  final _PhaseMusicProfile profile;
  final bool autoProfileEnabled;
  final bool isMusicPlaying;
  final double playbackSpeed;
  final ValueChanged<bool> onAutoProfileChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq_rounded, color: Colors.white70),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Phase Music Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: autoProfileEnabled,
                onChanged: onAutoProfileChanged,
              ),
            ],
          ),
          Text(
            '${profile.label}: ${profile.bpmRange}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            isMusicPlaying
                ? 'Auto speed ${playbackSpeed.toStringAsFixed(2)}x'
                : 'Pick and play a track to apply tempo profiles automatically.',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MusicChip extends StatelessWidget {
  const _MusicChip({
    required this.loading,
    required this.onTap,
    required this.selectedSongTitle,
  });

  final bool loading;
  final VoidCallback onTap;
  final String? selectedSongTitle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.library_music_rounded, color: Colors.white70),
            const SizedBox(width: 8),
            Text(
              selectedSongTitle == null ? 'Music' : 'Track set',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0.0)],
          ),
        ),
      ),
    );
  }
}
