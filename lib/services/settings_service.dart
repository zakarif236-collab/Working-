import 'package:my_app/models/workout_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class SettingsService {
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = AppSettings.defaults();

    final intensityIndex = prefs.getInt(_kIntensityIndex) ?? defaults.config.intensity.index;
    final intensity = WorkoutIntensity.values[intensityIndex.clamp(0, WorkoutIntensity.values.length - 1)];

    final config = WorkoutConfig(
      sets: prefs.getInt(_kSets) ?? defaults.config.sets,
      workSeconds: prefs.getInt(_kWorkSeconds) ?? defaults.config.workSeconds,
      restSeconds: prefs.getInt(_kRestSeconds) ?? defaults.config.restSeconds,
      warmupSeconds: prefs.getInt(_kWarmupSeconds) ?? defaults.config.warmupSeconds,
      cooldownSeconds: prefs.getInt(_kCooldownSeconds) ?? defaults.config.cooldownSeconds,
      intensity: intensity,
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

    await prefs.setBool(_kVoiceCueEnabled, settings.voiceCueEnabled);
    await prefs.setBool(_kHapticCueEnabled, settings.hapticCueEnabled);
    await prefs.setBool(_kMuteVoiceWhileMusicPlays, settings.muteVoiceWhileMusicPlays);
    await prefs.setDouble(_kVoiceCueVolume, settings.voiceCueVolume);
    await prefs.setDouble(_kVoiceCueRate, settings.voiceCueRate);
  }
}

const _kSets = 'settings.sets';
const _kWorkSeconds = 'settings.workSeconds';
const _kRestSeconds = 'settings.restSeconds';
const _kWarmupSeconds = 'settings.warmupSeconds';
const _kCooldownSeconds = 'settings.cooldownSeconds';
const _kIntensityIndex = 'settings.intensityIndex';

const _kVoiceCueEnabled = 'settings.voiceCueEnabled';
const _kHapticCueEnabled = 'settings.hapticCueEnabled';
const _kMuteVoiceWhileMusicPlays = 'settings.muteVoiceWhileMusicPlays';
const _kVoiceCueVolume = 'settings.voiceCueVolume';
const _kVoiceCueRate = 'settings.voiceCueRate';
