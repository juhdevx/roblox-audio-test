package com.voiceshift.diagnostics

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DiagnosticsTest {

    @Test
    fun procStatParsingHandlesSpacesInName() {
        val stat = "1234 (voice shift (main)) S 1 1234 0 0 -1 4194560 100 0 0 0 250 75 0 0 20 0 30 0 5000 0"
        assertEquals(325L, ProcStat.cpuTicks(stat))
        assertNull(ProcStat.cpuTicks("garbage"))
        assertEquals(50f, ProcStat.cpuPercent(ticksDelta = 50, ticksPerSecond = 100, wallDeltaMs = 1000), 1e-4f)
        assertEquals(0f, ProcStat.cpuPercent(10, 100, 0), 0f)
    }

    @Test
    fun logIsBoundedAndPersistedWithRotation() {
        val dir = Files.createTempDirectory("vs-log").toFile()
        val file = File(dir, "voiceshift.log")
        var t = 0L
        val log = DiagnosticsLog(file, capacity = 3, maxFileBytes = 200, clock = { t++ })
        repeat(10) { log.i("Test", "message number $it") }
        assertEquals(3, log.entries.value.size)
        assertEquals("message number 9", log.entries.value.last().message)
        assertTrue(File(dir, "voiceshift.log.1").exists())
        assertTrue(log.exportText().contains("message number 9"))
        log.clear()
        assertTrue(log.entries.value.isEmpty())
    }

    @Test
    fun reportRendersSectionsAndLogs() {
        val entries = listOf(LogEntry(0, LogLevel.WARN, "Engine", "disconnected"))
        val text = DiagnosticReport.Builder()
            .section("Device", listOf("Model" to "Test", "Android" to "15"))
            .logs(entries)
            .build()
            .render()
        assertTrue(text.contains("## Device"))
        assertTrue(text.contains("Model   : Test"))
        assertTrue(text.contains("disconnected"))
    }

    @Test
    fun thermalMapping() {
        assertEquals(ThermalLevel.NONE, ThermalLevel.fromPowerManager(0))
        assertEquals(ThermalLevel.SEVERE, ThermalLevel.fromPowerManager(3))
        assertTrue(ThermalLevel.SEVERE.throttlingLikely)
        assertEquals(ThermalLevel.UNKNOWN, ThermalLevel.fromPowerManager(42))
    }
}
