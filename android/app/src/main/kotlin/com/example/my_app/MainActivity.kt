package com.example.my_app

import android.media.ToneGenerator
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.my_app/audio"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playCountdownBeep" -> {
                        playCountdownBeep()
                        result.success(null)
                    }
                    "playCompletionBeep" -> {
                        playCompletionBeep()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun playCountdownBeep() {
        // High frequency beep for countdown (1000 Hz)
        val toneGenerator = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 100)
        toneGenerator.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 150)
        Thread.sleep(150)
        toneGenerator.release()
    }

    private fun playCompletionBeep() {
        // Different tone for completion - use a lower frequency with longer duration
        val toneGenerator = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 100)
        toneGenerator.startTone(ToneGenerator.TONE_CDMA_CONFIRM, 300)
        Thread.sleep(300)
        toneGenerator.release()
    }
}

