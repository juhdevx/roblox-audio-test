package com.voiceshift.diagnostics

import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class LogLevel { DEBUG, INFO, WARN, ERROR }

data class LogEntry(val timeMs: Long, val level: LogLevel, val tag: String, val message: String) {
    fun format(): String = "${timestamp(timeMs)} ${level.name.padEnd(5)} [$tag] $message"

    companion object {
        private val formatter = ThreadLocal.withInitial {
            SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).apply { timeZone = TimeZone.getDefault() }
        }
        fun timestamp(ms: Long): String = formatter.get()!!.format(Date(ms))
    }
}

/**
 * In-memory ring of recent diagnostic events, mirrored to a rotating file in app-private storage
 * so a crash or a long session can still be exported. Never sent anywhere automatically.
 */
class DiagnosticsLog(
    private val file: File?,
    private val capacity: Int = 500,
    private val maxFileBytes: Long = 1_000_000,
    private val clock: () -> Long = System::currentTimeMillis,
    private val platformLog: (LogLevel, String, String) -> Unit = { _, _, _ -> },
) {
    private val buffer = ArrayDeque<LogEntry>(capacity)
    private val _entries = MutableStateFlow<List<LogEntry>>(emptyList())
    val entries: StateFlow<List<LogEntry>> = _entries.asStateFlow()

    fun log(level: LogLevel, tag: String, message: String) {
        val entry = LogEntry(clock(), level, tag, message.take(2000))
        platformLog(level, tag, entry.message)
        synchronized(buffer) {
            if (buffer.size == capacity) buffer.removeFirst()
            buffer.addLast(entry)
            _entries.value = buffer.toList()
            appendToFile(entry)
        }
    }

    fun d(tag: String, message: String) = log(LogLevel.DEBUG, tag, message)
    fun i(tag: String, message: String) = log(LogLevel.INFO, tag, message)
    fun w(tag: String, message: String) = log(LogLevel.WARN, tag, message)
    fun e(tag: String, message: String) = log(LogLevel.ERROR, tag, message)

    fun clear() = synchronized(buffer) {
        buffer.clear()
        _entries.value = emptyList()
        file?.delete()
    }

    /** Current file content plus the previous rotated file, oldest first. */
    fun exportText(): String = synchronized(buffer) {
        val f = file ?: return buffer.joinToString("\n") { it.format() }
        val old = File(f.parentFile, f.name + ".1")
        buildString {
            if (old.exists()) append(old.readText())
            if (f.exists()) append(f.readText())
        }
    }

    private fun appendToFile(entry: LogEntry) {
        val f = file ?: return
        try {
            f.parentFile?.mkdirs()
            if (f.exists() && f.length() > maxFileBytes) {
                val old = File(f.parentFile, f.name + ".1")
                old.delete()
                f.renameTo(old)
            }
            f.appendText(entry.format() + "\n")
        } catch (_: Exception) {
            // Logging must never crash the app (e.g. storage full).
        }
    }
}
