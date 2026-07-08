import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class CueService {
  CueService() : _tts = _supportsVoiceCues ? FlutterTts() : null;

  static bool get _supportsVoiceCues =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.windows;

  final FlutterTts? _tts;
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

  /// Speak countdown - handles 5, 4, 3, 2, 1 countdown
  Future<void> speakCount(int seconds) async {
    if (seconds < 1 || seconds > 5 || _tts == null) {
      return;
    }

    final tts = _tts;
    await _configureTts();
    await tts.speak('$seconds');
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
  }

  Future<void> dispose() async {
    await _tts?.stop();
  }
}

class CueServiceException implements Exception {
  const CueServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
