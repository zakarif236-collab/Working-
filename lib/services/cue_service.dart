import 'package:flutter_tts/flutter_tts.dart';

class CueService {
  CueService() : _tts = FlutterTts();

  final FlutterTts _tts;
  double _volume = 1.0;
  double _speechRate = 0.52;

  Future<void> updateSettings({double? volume, double? speechRate}) async {
    if (volume != null) {
      _volume = volume.clamp(0.0, 1.0);
    }
    if (speechRate != null) {
      _speechRate = speechRate.clamp(0.2, 0.8);
    }

    try {
      await _tts.setVolume(_volume);
      await _tts.setSpeechRate(_speechRate);
    } catch (e) {
      throw CueServiceException('Unable to apply voice cue settings: $e');
    }
  }

  Future<void> announcePhase(String phaseLabel) async {
    await _configureTts();
    await _tts.speak('$phaseLabel phase');
  }

  Future<void> speakCount(int seconds) async {
    if (seconds < 1) {
      return;
    }

    await _configureTts();
    await _tts.speak('$seconds');
  }

  Future<void> announceCompletion() async {
    await _configureTts();
    await _tts.speak('Workout complete. Great job.');
  }

  Future<void> _configureTts() async {
    try {
      await _tts.setVolume(_volume);
      await _tts.setPitch(1.05);
      await _tts.setSpeechRate(_speechRate);
      await _tts.awaitSpeakCompletion(true);
    } catch (e) {
      throw CueServiceException('Voice cues are unavailable on this device: $e');
    }
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}

class CueServiceException implements Exception {
  const CueServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
