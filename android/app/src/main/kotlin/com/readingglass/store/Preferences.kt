package com.readingglass.store

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.readingglass.models.PronunciationEntry
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

private const val FILE = "reading_glass_prefs"

private const val KEY_SKIP_CITATIONS = "skipCitations"
private const val KEY_REPLACE_PARENS = "replaceParentheses"
private const val KEY_SPEAK_GREEK = "speakGreekLetters"
private const val KEY_SPEAK_MATH = "speakMathSymbols"
private const val KEY_IGNORE_REFERENCES = "ignoreReferences"
private const val KEY_IGNORE_BEFORE_ABSTRACT = "ignoreBeforeAbstract"
private const val KEY_SPEED = "speedMultiplier"
private const val KEY_VOICE = "voiceName"
private const val KEY_PRONUNCIATIONS = "pronunciations"

/**
 * Compose-friendly preferences store. Each field exposes a regular Kotlin property
 * whose setter both updates the in-memory state (triggering recomposition) and
 * writes through to SharedPreferences.
 */
class Preferences private constructor(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    var skipCitations by mutableStateOf(prefs.getBoolean(KEY_SKIP_CITATIONS, true))
    var replaceParentheses by mutableStateOf(prefs.getBoolean(KEY_REPLACE_PARENS, true))
    var speakGreekLetters by mutableStateOf(prefs.getBoolean(KEY_SPEAK_GREEK, true))
    var speakMathSymbols by mutableStateOf(prefs.getBoolean(KEY_SPEAK_MATH, true))
    var ignoreReferences by mutableStateOf(prefs.getBoolean(KEY_IGNORE_REFERENCES, true))
    var ignoreBeforeAbstract by mutableStateOf(prefs.getBoolean(KEY_IGNORE_BEFORE_ABSTRACT, true))
    var speedMultiplier by mutableStateOf(prefs.getFloat(KEY_SPEED, 2.0f))
    var voiceName by mutableStateOf(prefs.getString(KEY_VOICE, "") ?: "")
    var pronunciations by mutableStateOf(loadPronunciations())

    fun persistBooleans() {
        prefs.edit()
            .putBoolean(KEY_SKIP_CITATIONS, skipCitations)
            .putBoolean(KEY_REPLACE_PARENS, replaceParentheses)
            .putBoolean(KEY_SPEAK_GREEK, speakGreekLetters)
            .putBoolean(KEY_SPEAK_MATH, speakMathSymbols)
            .putBoolean(KEY_IGNORE_REFERENCES, ignoreReferences)
            .putBoolean(KEY_IGNORE_BEFORE_ABSTRACT, ignoreBeforeAbstract)
            .apply()
    }

    fun setSpeed(value: Float) {
        speedMultiplier = value
        prefs.edit().putFloat(KEY_SPEED, value).apply()
    }

    fun setVoice(name: String) {
        voiceName = name
        prefs.edit().putString(KEY_VOICE, name).apply()
    }

    fun setPronunciations(list: List<PronunciationEntry>) {
        pronunciations = list
        prefs.edit().putString(KEY_PRONUNCIATIONS, json.encodeToString(list)).apply()
    }

    private fun loadPronunciations(): List<PronunciationEntry> {
        val raw = prefs.getString(KEY_PRONUNCIATIONS, null) ?: return defaultPronunciations
        return runCatching { json.decodeFromString<List<PronunciationEntry>>(raw) }
            .getOrDefault(defaultPronunciations)
    }

    companion object {
        @Volatile private var instance: Preferences? = null
        fun get(context: Context): Preferences =
            instance ?: synchronized(this) {
                instance ?: Preferences(context).also { instance = it }
            }

        val defaultPronunciations = listOf(
            PronunciationEntry(find = "vCPU", replace = "virtual CPU"),
            PronunciationEntry(find = "e.g.", replace = "for example"),
            PronunciationEntry(find = "i.e.", replace = "that is"),
            PronunciationEntry(find = "et al.", replace = "and others"),
            PronunciationEntry(find = "Fig.", replace = "Figure"),
        )
    }
}
