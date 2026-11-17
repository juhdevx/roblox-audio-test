package com.voiceshift.models

import java.io.File
import java.io.IOException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json

/**
 * A single JSON document on disk, exposed as a [StateFlow].
 *
 * * Writes are atomic: content goes to a temp file that is then renamed over the original, so a crash
 *   or power loss never leaves a half-written file.
 * * A corrupt file is moved aside (`*.corrupt-<time>`) and the store falls back to [default] instead
 *   of crashing the app.
 * * Unknown keys are ignored so older app versions can read newer files.
 */
class JsonFileStore<T>(
    private val file: File,
    private val serializer: KSerializer<T>,
    private val default: T,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val mutex = Mutex()
    private val _value = MutableStateFlow(load())
    val value: StateFlow<T> = _value.asStateFlow()

    /** Set when the last load had to discard a corrupt file. */
    var recoveredFromCorruption: Boolean = false
        private set

    private fun load(): T {
        if (!file.exists()) return default
        return try {
            JSON.decodeFromString(serializer, file.readText())
        } catch (e: Exception) {
            val aside = File(file.parentFile, "${file.name}.corrupt-${clock()}")
            file.renameTo(aside)
            recoveredFromCorruption = true
            default
        }
    }

    suspend fun update(transform: (T) -> T): T = mutex.withLock {
        val next = transform(_value.value)
        if (next != _value.value) {
            write(next)
            _value.value = next
        }
        next
    }

    suspend fun set(newValue: T) {
        update { newValue }
    }

    private fun write(content: T) {
        file.parentFile?.mkdirs()
        val tmp = File(file.parentFile, "${file.name}.tmp")
        tmp.writeText(JSON.encodeToString(serializer, content))
        if (!tmp.renameTo(file)) {
            // renameTo can fail on some filesystems when the target exists; fall back to delete + rename.
            file.delete()
            if (!tmp.renameTo(file)) throw IOException("Could not replace ${file.absolutePath}")
        }
    }

    companion object {
        val JSON = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
            prettyPrint = true
            coerceInputValues = true
        }
    }
}
