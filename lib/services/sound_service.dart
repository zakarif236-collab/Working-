import 'package:flutter/services.dart';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  
  static const _channel = MethodChannel('com.example.my_app/audio');
  
  factory SoundService() {
    return _instance;
  }
  
  SoundService._internal();

  /// Play a countdown beep sound (used for 3, 2, 1 countdown)
  /// High frequency, short beep
  Future<void> playCountdownBeep() async {
    try {
      await _channel.invokeMethod('playCountdownBeep');
    } catch (e) {
      // Silently fail if platform doesn't support it
    }
  }

  /// Play a completion sound (used when exercise/phase completes)
  /// Different tone from countdown beep - typically lower frequency
  Future<void> playCompletionBeep() async {
    try {
      await _channel.invokeMethod('playCompletionBeep');
    } catch (e) {
      // Silently fail if platform doesn't support it
    }
  }

  Future<void> dispose() async {
    // Cleanup if needed
  }
}

