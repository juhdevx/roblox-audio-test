package com.voiceshift.diagnostics

/**
 * Plain-text diagnostic report the user can share (Android share sheet) when asking for help.
 * Contains device/engine facts and recent logs; no audio, no account data, no model files.
 */
class DiagnosticReport private constructor(private val sections: List<Pair<String, List<Pair<String, String>>>>) {

    fun render(): String = buildString {
        appendLine("VoiceShift VR diagnostic report")
        appendLine("=".repeat(32))
        for ((title, rows) in sections) {
            appendLine()
            appendLine("## $title")
            val width = rows.maxOfOrNull { it.first.length } ?: 0
            for ((k, v) in rows) appendLine("${k.padEnd(width)} : $v")
        }
    }

    class Builder {
        private val sections = mutableListOf<Pair<String, List<Pair<String, String>>>>()

        fun section(title: String, rows: List<Pair<String, String>>) = apply { sections += title to rows }

        fun logs(entries: List<LogEntry>, limit: Int = 200) = apply {
            sections += "Recent log (${minOf(limit, entries.size)} of ${entries.size})" to
                entries.takeLast(limit).mapIndexed { i, e -> "%03d".format(i) to e.format() }
        }

        fun build() = DiagnosticReport(sections.toList())
    }
}
