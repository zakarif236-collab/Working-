import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_app/controllers/workout_controller.dart';
import 'package:my_app/models/workout_models.dart';
import 'package:my_app/services/cue_service.dart';
import 'package:my_app/services/music_service.dart';
import 'package:my_app/services/settings_service.dart';
import 'package:my_app/services/sound_service.dart';
import 'package:my_app/widgets/circular_countdown.dart';
import 'package:my_app/widgets/workout_timeline.dart';
import 'package:on_audio_query/on_audio_query.dart';

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
  late final SoundService _soundService;
  late final SettingsService _settingsService;
  late final AnimationController _pulseController;
  Timer? _settingsPersistDebounce;

  WorkoutIntensity _selectedIntensity = WorkoutConfig.defaults.intensity;
  List<SongModel> _songs = const [];
  bool _loadingSongs = false;
  bool _voiceCueEnabled = true;
  bool _hapticCueEnabled = true;
  bool _muteVoiceWhileMusicPlays = true;
  double _voiceCueVolume = 1.0;
  double _voiceCueRate = 0.52;
  int _lastAnnouncedSeconds = -1;
  int _lastObservedPhaseIndex = -1;
  bool _didAnnounceCompletion = false;

  @override
  void initState() {
    super.initState();
    _controller = WorkoutController();
    _musicService = MusicService();
    _cueService = CueService();
    _soundService = SoundService();
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

    _controller.addListener(_watchWorkoutErrors);
  }

  @override
  void dispose() {
    _settingsPersistDebounce?.cancel();
    _controller.removeListener(_watchWorkoutErrors);
    _controller.dispose();
    _pulseController.dispose();
    _cueService.dispose();
    _soundService.dispose();
    _musicService.dispose();
    super.dispose();
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
        _voiceCueEnabled = _cueService.supportsVoiceCues && saved.voiceCueEnabled;
        _hapticCueEnabled = saved.hapticCueEnabled;
        _muteVoiceWhileMusicPlays = saved.muteVoiceWhileMusicPlays;
        _voiceCueVolume = saved.voiceCueVolume;
        _voiceCueRate = saved.voiceCueRate;
      });
    } catch (e) {
      if (mounted) {
        _showMessage('Could not restore your saved settings. Using defaults.');
      }
    }
  }

  void _scheduleSettingsPersist() {
    _settingsPersistDebounce?.cancel();
    _settingsPersistDebounce = Timer(const Duration(milliseconds: 300), () async {
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
          _showMessage('Saving settings failed. We will try again on your next change.');
        }
      }
    });
  }

  Future<void> _handleWorkoutCues() async {
    final phaseIndex = _controller.phaseIndex;
    final remaining = _controller.remainingSeconds;
    final canSpeak = _voiceCueEnabled &&
        !(_muteVoiceWhileMusicPlays && _musicService.player.playing);

    if (_controller.isRunning && phaseIndex != _lastObservedPhaseIndex) {
      _lastObservedPhaseIndex = phaseIndex;

      if (!_controller.isComplete && phaseIndex < _controller.timeline.length) {
        if (_hapticCueEnabled) {
          await HapticFeedback.mediumImpact();
        }
        if (canSpeak) {
          try {
            await _cueService.announcePhase(_phaseLabel(_controller.currentPhase));
          } on CueServiceException catch (e) {
            _showMessage(e.message);
          }
        }
      }
    }

    if (_controller.isRunning && remaining != _lastAnnouncedSeconds) {
      _lastAnnouncedSeconds = remaining;
      // Countdown from 5 to 1
      if (remaining > 0 && remaining <= 5) {
        if (_hapticCueEnabled) {
          await HapticFeedback.selectionClick();
        }
        // Speak the countdown if voice is enabled
        if (canSpeak) {
          try {
            await _cueService.speakCount(remaining);
          } on CueServiceException catch (e) {
            _showMessage(e.message);
          }
        }
        // Play beep sound on 3, 2, 1 (always, even if voice is disabled)
        if (remaining <= 3) {
          try {
            await _soundService.playCountdownBeep();
          } catch (e) {
            // Silently fail for beep sound
          }
        }
      }
    }

    if (_controller.isComplete && !_didAnnounceCompletion) {
      _didAnnounceCompletion = true;
      if (_hapticCueEnabled) {
        await HapticFeedback.heavyImpact();
      }
      // Play completion beep sound (always, regardless of voice setting)
      try {
        await _soundService.playCompletionBeep();
      } catch (e) {
        // Silently fail for completion beep
      }
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
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
                        final selected = _musicService.currentSong?.id == song.id;
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
                colors: [
                  palette[0],
                  const Color(0xFF0D121C),
                  palette[1],
                ],
                stops: const [0.0, 0.48, 1.0],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -60,
                  left: -40,
                  child: _GlowBlob(color: palette.first.withValues(alpha: 0.55)),
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Immersive Workout Timer',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 20,
                              ),
                            ),
                            _MusicChip(
                              loading: _loadingSongs,
                              onTap: _openMusicPicker,
                              selectedSongTitle: _musicService.currentSong?.title,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          children: [
                            _ConfigPanel(
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
                              muteVoiceWhileMusicPlays: _muteVoiceWhileMusicPlays,
                              onMuteVoiceWhileMusicChanged: (value) {
                                setState(() {
                                  _muteVoiceWhileMusicPlays = value;
                                });
                                if (value && _musicService.player.playing) {
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
                                  await _cueService.updateSettings(volume: value);
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
                                  await _cueService.updateSettings(speechRate: value);
                                } on CueServiceException catch (e) {
                                  if (mounted) {
                                    _showMessage(e.message);
                                  }
                                }
                                _scheduleSettingsPersist();
                              },
                            ),
                            const SizedBox(height: 14),
                            ScaleTransition(
                              scale: _pulseController,
                              child: CircularCountdown(
                                progress: _controller.phaseProgress,
                                seconds: _controller.remainingSeconds,
                                label: _phaseLabel(phase),
                                gradient: [palette.first, palette.last],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _ProgressHeader(
                              progress: _controller.totalProgress,
                              elapsed: _controller.elapsedWorkoutSeconds,
                              total: _controller.totalWorkoutSeconds,
                            ),
                            const SizedBox(height: 10),
                            WorkoutTimeline(
                              timeline: _controller.timeline,
                              currentIndex: _controller.phaseIndex,
                            ),
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
                              onReset: () => _controller.stop(reset: true),
                              onSkip: _controller.skipPhase,
                              onMusicToggle: () async {
                                try {
                                  await _musicService.togglePlayPause();
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
  }) onChanged;
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
            max: 50,
            divisions: 49,
            onChanged: (v) => onChanged(sets: v.round()),
          ),
          _LabeledSlider(
            label: 'Work: ${config.workSeconds}s',
            value: config.workSeconds.toDouble(),
            min: 10,
            max: 120,
            divisions: 22,
            onChanged: (v) => onChanged(work: v.round()),
          ),
          _LabeledSlider(
            label: 'Rest: ${config.restSeconds}s',
            value: config.restSeconds.toDouble(),
            min: 5,
            max: 90,
            divisions: 17,
            onChanged: (v) => onChanged(rest: v.round()),
          ),
          _LabeledSlider(
            label: 'Warmup: ${config.warmupSeconds}s',
            value: config.warmupSeconds.toDouble(),
            min: 0,
            max: 60,
            divisions: 12,
            onChanged: (v) => onChanged(warmup: v.round()),
          ),
          _LabeledSlider(
            label: 'Cooldown: ${config.cooldownSeconds}s',
            value: config.cooldownSeconds.toDouble(),
            min: 0,
            max: 60,
            divisions: 12,
            onChanged: (v) => onChanged(cooldown: v.round()),
          ),
          const SizedBox(height: 6),
          const Text(
            'Intensity',
            style: TextStyle(color: Colors.white70),
          ),
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
          Switch(
            value: value,
            onChanged: onChanged,
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        Slider(
          value: value,
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
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
          label: Text(running ? 'Pause' : complete ? 'Restart' : 'Start'),
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
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
            colors: [
              color,
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}
