package com.readingglass.managers

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.Locale

/**
 * Wraps Android's [TextToSpeech] with cursor-tracking semantics that mirror
 * the macOS/iPadOS `SpeechManager`.
 *
 * Word offsets are reported in UTF-16 code units, identical to the Swift impl.
 */
class SpeechManager(context: Context) {

    var isPlaying by mutableStateOf(false)
        private set
    var isPaused by mutableStateOf(false)
        private set

    /** Cursor position as a UTF-16 offset into the full text. */
    var cursorUtf16 by mutableIntStateOf(0)
    var cursorLengthUtf16 by mutableIntStateOf(0)

    val availableVoices = mutableStateListOf<Voice>()
    var selectedVoiceName by mutableStateOf("")

    /** 0.5x – 4.0x. Mapped to TTS speech rate on each utterance. */
    var speedMultiplier: Float = 2.0f

    private var fullText: String = ""
    private var speakingUtf16Offset: Int = 0
    private var isReady = false

    private val utteranceId = "reading-glass-utterance"

    private val tts: TextToSpeech = TextToSpeech(context.applicationContext) { status ->
        if (status == TextToSpeech.SUCCESS) {
            isReady = true
            loadVoices()
        }
    }

    init {
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}

            override fun onRangeStart(uid: String?, start: Int, end: Int, frame: Int) {
                val absLocation = speakingUtf16Offset + start
                val absLength = end - start
                val total = fullText.length
                if (absLocation + absLength > total) return
                cursorUtf16 = absLocation
                cursorLengthUtf16 = absLength
            }

            override fun onDone(utteranceId: String?) {
                isPlaying = false
                isPaused = false
            }

            @Deprecated("Required by interface")
            override fun onError(utteranceId: String?) {
                isPlaying = false
                isPaused = false
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
                isPlaying = false
                isPaused = false
            }

            override fun onStop(uid: String?, interrupted: Boolean) {
                isPlaying = false
                isPaused = false
            }
        })
    }

    private fun loadVoices() {
        val voices = tts.voices ?: return
        // English voices, deduplicated by display name, sorted alphabetically.
        val seen = HashSet<String>()
        availableVoices.clear()
        voices
            .filter { it.locale.language == "en" }
            .filterNot { it.isNetworkConnectionRequired }
            .sortedBy { it.name.lowercase() }
            .forEach { if (seen.add(it.name)) availableVoices.add(it) }

        if (selectedVoiceName.isEmpty()) {
            val preferred = availableVoices.firstOrNull { it.locale == Locale.US }
                ?: availableVoices.firstOrNull()
            preferred?.let { selectedVoiceName = it.name }
        }
        applySelectedVoice()
    }

    private fun applySelectedVoice() {
        val v = availableVoices.firstOrNull { it.name == selectedVoiceName }
        if (v != null) {
            tts.voice = v
            tts.language = v.locale
        } else {
            tts.language = Locale.US
        }
    }

    fun setVoice(name: String) {
        selectedVoiceName = name
        if (isPlaying) stop()
        applySelectedVoice()
    }

    fun setRate(multiplier: Float) {
        speedMultiplier = multiplier
        if (isPlaying) stop()
    }

    /**
     * Maps our 0.5x-4x multiplier to TTS's natively-meaningful rate.
     * Android's setSpeechRate scale is roughly linear around 1.0, so we forward
     * it directly with a sensible clamp.
     */
    private fun rateForTts(): Float = speedMultiplier.coerceIn(0.5f, 4.0f)

    fun play(text: String) {
        fullText = text
        if (text.isEmpty() || !isReady) return

        tts.stop()
        val clampedOffset = cursorUtf16.coerceIn(0, text.length)
        val substring = text.substring(clampedOffset)
        if (substring.isEmpty()) return

        speakingUtf16Offset = clampedOffset
        tts.setSpeechRate(rateForTts())
        applySelectedVoice()

        val params = Bundle().apply {
            putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
        }
        tts.speak(substring, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
        isPlaying = true
        isPaused = false
    }

    fun pause() {
        tts.stop()
        isPlaying = false
        isPaused = false
    }

    fun stop() {
        tts.stop()
        isPlaying = false
        isPaused = false
    }

    /** Highlighted character range for [text] at the current cursor, or null. */
    fun highlightRange(text: String): IntRange? {
        if (text.isEmpty()) return null
        val start = cursorUtf16.coerceIn(0, text.length)
        if (start >= text.length) return null
        if (cursorLengthUtf16 == 0) {
            var wordEnd = start
            while (wordEnd < text.length && !text[wordEnd].isWhitespace()) wordEnd++
            if (wordEnd == start && start < text.length) wordEnd = start + 1
            return start until wordEnd
        }
        val end = (cursorUtf16 + cursorLengthUtf16).coerceAtMost(text.length)
        return if (end <= start) start until (start + 1).coerceAtMost(text.length)
        else start until end
    }

    fun skipForward(text: String) {
        stop()
        if (cursorUtf16 >= text.length) return
        val tail = text.substring(cursorUtf16)
        val idx = tail.indexOfAny(charArrayOf('.', '!', '?'))
        if (idx < 0) return
        var next = cursorUtf16 + idx + 1
        while (next < text.length && text[next].isWhitespace()) next++
        if (next < text.length) {
            cursorUtf16 = next
            cursorLengthUtf16 = 0
        }
    }

    fun skipBackward(text: String) {
        stop()
        if (cursorUtf16 == 0 || text.isEmpty()) return
        val clamped = cursorUtf16.coerceAtMost(text.length)
        var searchEnd = clamped
        while (searchEnd > 0) {
            val prev = searchEnd - 1
            val c = text[prev]
            if (c.isWhitespace() || c == '.' || c == '!' || c == '?') searchEnd = prev else break
        }
        val before = text.substring(0, searchEnd)
        val idx = before.indexOfLast { it == '.' || it == '!' || it == '?' }
        cursorUtf16 = if (idx < 0) 0 else {
            var s = idx + 1
            while (s < text.length && text[s].isWhitespace()) s++
            s
        }
        cursorLengthUtf16 = 0
    }

    fun resetCursor() {
        cursorUtf16 = 0
        cursorLengthUtf16 = 0
    }

    fun shutdown() {
        tts.stop()
        tts.shutdown()
    }
}
