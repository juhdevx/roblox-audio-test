package com.voiceshift.diagnostics

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.system.Os
import android.system.OsConstants
import java.io.File

enum class ThermalLevel(val label: String) {
    NONE("Normal"), LIGHT("Light"), MODERATE("Moderate"), SEVERE("Severe"),
    CRITICAL("Critical"), EMERGENCY("Emergency"), SHUTDOWN("Shutdown"), UNKNOWN("Unknown");

    val throttlingLikely: Boolean get() = this in setOf(MODERATE, SEVERE, CRITICAL, EMERGENCY, SHUTDOWN)

    companion object {
        /** Maps PowerManager.THERMAL_STATUS_* (0..6). */
        fun fromPowerManager(status: Int): ThermalLevel = entries.getOrElse(status) { UNKNOWN }
    }
}

data class PerfSnapshot(
    /** Process CPU time as a percentage of one core since the previous sample. */
    val cpuPercentOfOneCore: Float,
    val cores: Int,
    val javaHeapUsedMb: Float,
    val nativeHeapMb: Float,
    val availableSystemMb: Float,
    val lowMemory: Boolean,
    val thermal: ThermalLevel,
    /** 0..1 forecast of thermal headroom (1 = throttling imminent), null if unsupported. */
    val thermalHeadroom: Float?,
)

/** Parses utime + stime (clock ticks) from the content of /proc/<pid>/stat. Pure; unit-tested. */
object ProcStat {
    fun cpuTicks(stat: String): Long? {
        // The command name (field 2) is in parentheses and may contain spaces.
        val afterName = stat.substringAfterLast(')', missingDelimiterValue = "").trim()
        if (afterName.isEmpty()) return null
        val fields = afterName.split(Regex("\\s+"))
        // afterName starts at field 3 (state); utime = field 14, stime = field 15.
        val utime = fields.getOrNull(14 - 3)?.toLongOrNull() ?: return null
        val stime = fields.getOrNull(15 - 3)?.toLongOrNull() ?: return null
        return utime + stime
    }

    fun cpuPercent(ticksDelta: Long, ticksPerSecond: Long, wallDeltaMs: Long): Float =
        if (wallDeltaMs <= 0 || ticksPerSecond <= 0) 0f else 100f * ticksDelta * 1000f / ticksPerSecond / wallDeltaMs
}

/** Samples CPU, memory and thermal state. Call [sample] from a background coroutine every ~1 s. */
class PerformanceMonitor(context: Context) {
    private val activityManager = context.getSystemService(ActivityManager::class.java)
    private val powerManager = context.getSystemService(PowerManager::class.java)
    private val ticksPerSecond = runCatching { Os.sysconf(OsConstants._SC_CLK_TCK) }.getOrDefault(100L)
    private val statFile = File("/proc/${Process.myPid()}/stat")
    private var lastTicks: Long? = null
    private var lastWallMs = 0L

    fun sample(): PerfSnapshot {
        val now = SystemClock.elapsedRealtime()
        val ticks = runCatching { ProcStat.cpuTicks(statFile.readText()) }.getOrNull()
        val cpu = if (ticks != null && lastTicks != null) {
            ProcStat.cpuPercent(ticks - lastTicks!!, ticksPerSecond, now - lastWallMs)
        } else {
            0f
        }
        lastTicks = ticks
        lastWallMs = now

        val runtime = Runtime.getRuntime()
        val memInfo = ActivityManager.MemoryInfo().also { activityManager.getMemoryInfo(it) }
        val headroom = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            runCatching { powerManager.getThermalHeadroom(10) }.getOrNull()?.takeIf { !it.isNaN() }
        } else {
            null
        }
        return PerfSnapshot(
            cpuPercentOfOneCore = cpu,
            cores = runtime.availableProcessors(),
            javaHeapUsedMb = (runtime.totalMemory() - runtime.freeMemory()) / MB,
            nativeHeapMb = Debug.getNativeHeapAllocatedSize() / MB,
            availableSystemMb = memInfo.availMem / MB,
            lowMemory = memInfo.lowMemory,
            thermal = ThermalLevel.fromPowerManager(powerManager.currentThermalStatus),
            thermalHeadroom = headroom,
        )
    }

    fun availableMemoryBytes(): Long = ActivityManager.MemoryInfo().also { activityManager.getMemoryInfo(it) }.availMem
    fun isLowRamDevice(): Boolean = activityManager.isLowRamDevice

    private companion object {
        const val MB = 1024f * 1024f
    }
}
