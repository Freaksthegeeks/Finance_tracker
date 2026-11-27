package com.financetracker.finance_tracker

import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class ExpensePlayback(private val activity: MainActivity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "finance_tracker/expense_playback")
    private var voice: TextToSpeech? = null
    private var voiceReady = false
    private var pendingPrompt: String? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "speak" -> {
                    (call.arguments as? String)?.let(::speak)
                    result.success(null)
                }
                "stopSpeaking" -> {
                    stopSpeaking()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        stopSpeaking()
        voice?.shutdown()
        voice = null
    }

    private fun speak(text: String) {
        pendingPrompt = text
        if (voice == null) {
            voice = TextToSpeech(activity) { status ->
                Handler(Looper.getMainLooper()).post {
                    val engine = voice ?: return@post
                    if (status == TextToSpeech.SUCCESS) {
                        val offline = engine.voices.orEmpty()
                            .filter { candidate ->
                                candidate.locale.language == "en" &&
                                    !candidate.isNetworkConnectionRequired &&
                                    TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED !in
                                        candidate.features.orEmpty()
                            }
                            .sortedByDescending { it.locale.country == "IN" }
                            .firstOrNull()
                        voiceReady = offline != null && engine.setVoice(offline) == TextToSpeech.SUCCESS
                    }
                    playPrompt()
                }
            }
        } else {
            playPrompt()
        }
    }

    private fun playPrompt() {
        if (!voiceReady) return
        val text = pendingPrompt ?: return
        pendingPrompt = null
        voice?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "expense-assistant")
    }

    fun stopSpeaking() {
        pendingPrompt = null
        voice?.stop()
    }

}
