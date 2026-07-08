import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

class CueService {
  CueService() 
    : _tts = _supportsVoiceCues ? FlutterTts() : null,
      _audioPlayer = AudioPlayer();

  static bool get _supportsVoiceCues =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.windows;

  final FlutterTts? _tts;
  final AudioPlayer _audioPlayer;
  double _volume = 1.0;
  double _speechRate = 0.52;

  bool get supportsVoiceCues => _supportsVoiceCues;

  Future<void> updateSettings({double? volume, double? speechRate}) async {
    if (volume != null) {
      _volume = volume.clamp(0.0, 1.0);
    }
    if (speechRate != null) {
      _speechRate = speechRate.clamp(0.2, 0.8);
    }

    if (_tts == null) {
      return;
    }

    final tts = _tts;

    try {
      await tts.setVolume(_volume);
      await tts.setSpeechRate(_speechRate);
    } catch (e) {
      throw CueServiceException('Unable to apply voice cue settings: $e');
    }
  }

  Future<void> announcePhase(String phaseLabel) async {
    if (_tts == null) {
      return;
    }
    final tts = _tts;
    await _configureTts();
    await tts.speak('$phaseLabel phase');
  }

  Future<void> speakCount(int seconds, {bool shouldSpeak = true}) async {
    // Always play beep sounds on 3, 2, 1 (even if voice is disabled)
    if (seconds > 0 && seconds <= 3) {
      await _playCountdownBeep();
    }

    // Play voice only if enabled and seconds > 0
    if (!shouldSpeak || seconds < 1 || _tts == null) {
      return;
    }

    final tts = _tts;
    await _configureTts();
    await tts.speak('$seconds');
  }

  Future<void> _playCountdownBeep() async {
    try {
      // Create a simple beep using just_audio's Tone source
      const audioSource = AudioSource.tone(frequency: 800.0, duration: Duration(milliseconds: 150));
      await _audioPlayer.setAudioSource(audioSource);
      await _audioPlayer.setVolume(_volume);
      await _audioPlayer.play();
    } catch (e) {
      // Silently fail if beep can't play
    }
  }

  Future<void> playPhaseCompletionBeep() async {
    try {
      // Play a higher frequency beep to indicate phase completion
      const audioSource = AudioSource.tone(frequency: 1200.0, duration: Duration(milliseconds: 300));
      await _audioPlayer.setAudioSource(audioSource);
      await _audioPlayer.setVolume(_volume);
      await _audioPlayer.play();
    } catch (e) {
      // Silently fail if beep can't play
    }
  }

  Future<void> playWorkoutCompletionBeep() async {
    try {
      // Play a two-tone beep sequence to indicate workout completion
      // First tone
      const firstTone = AudioSource.tone(frequency: 1000.0, duration: Duration(milliseconds: 200));
      await _audioPlayer.setAudioSource(firstTone);
      await _audioPlayer.setVolume(_volume);
      await _audioPlayer.play();
      await Future.delayed(const Duration(milliseconds: 250));
      
      // Second tone (higher frequency)
      const secondTone = AudioSource.tone(frequency: 1500.0, duration: Duration(milliseconds: 200));
      await _audioPlayer.setAudioSource(secondTone);
      await _audioPlayer.setVolume(_volume);
      await _audioPlayer.play();
    } catch (e) {
      // Silently fail if beep can't play
    }
  }

  Future<void> announceCompletion() async {
    if (_tts == null) {
      return;
    }
    final tts = _tts;
    await _configureTts();
    await tts.speak('Workout complete. Great job.');
  }

  Future<void> _configureTts() async {
    if (_tts == null) {
      return;
    }

    final tts = _tts;

    try {
      await tts.setVolume(_volume);
      await tts.setPitch(1.05);
      await tts.setSpeechRate(_speechRate);
      await tts.awaitSpeakCompletion(true);
    } catch (e) {
      throw CueServiceException('Voice cues are unavailable on this device: $e');
    }
  }

  Future<void> stop() async {
    await _tts?.stop();
    await _audioPlayer.stop();
  }

  Future<void> dispose() async {
    await _tts?.stop();
    await _audioPlayer.dispose();
  }
}

class CueServiceException implements Exception {
  const CueServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
