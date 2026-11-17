package com.voiceshift.vr.di

import android.content.Context
import android.util.Log
import com.voiceshift.audio.AndroidAudioDeviceSource
import com.voiceshift.audio.AudioDeviceSource
import com.voiceshift.audio.AudioEngineNative
import com.voiceshift.audio.EngineLog
import com.voiceshift.audio.OboeAudioEngineNative
import com.voiceshift.audio.VoiceEngineController
import com.voiceshift.bridge.usb.UsbAudioInspector
import com.voiceshift.diagnostics.DiagnosticsLog
import com.voiceshift.diagnostics.LogLevel
import com.voiceshift.diagnostics.PerformanceMonitor
import com.voiceshift.inference.OnnxModelValidator
import com.voiceshift.models.MemoryBudget
import com.voiceshift.models.ModelRegistry
import com.voiceshift.models.PresetRepository
import com.voiceshift.models.SettingsRepository
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import java.io.File
import javax.inject.Qualifier
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class AppScope

@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class IoDispatcher

/**
 * Composition root. Library modules stay framework-free (no Hilt annotations); everything is
 * wired here, which keeps the core modules testable on the JVM.
 */
@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides @Singleton @AppScope
    fun appScope(): CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    @Provides @IoDispatcher
    fun ioDispatcher(): CoroutineDispatcher = Dispatchers.IO

    @Provides @Singleton
    fun diagnosticsLog(@ApplicationContext context: Context): DiagnosticsLog = DiagnosticsLog(
        file = File(context.filesDir, "logs/voiceshift.log"),
        platformLog = { level, tag, message ->
            when (level) {
                LogLevel.DEBUG -> Log.d("VS/$tag", message)
                LogLevel.INFO -> Log.i("VS/$tag", message)
                LogLevel.WARN -> Log.w("VS/$tag", message)
                LogLevel.ERROR -> Log.e("VS/$tag", message)
            }
        },
    )

    @Provides @Singleton
    fun audioEngineNative(): AudioEngineNative = OboeAudioEngineNative()

    @Provides @Singleton
    fun audioDeviceSource(@ApplicationContext context: Context): AudioDeviceSource = AndroidAudioDeviceSource(context)

    @Provides @Singleton
    fun voiceEngineController(
        native: AudioEngineNative,
        devices: AudioDeviceSource,
        @AppScope scope: CoroutineScope,
        @IoDispatcher io: CoroutineDispatcher,
        log: DiagnosticsLog,
    ): VoiceEngineController = VoiceEngineController(
        native = native,
        deviceSource = devices,
        scope = scope,
        ioDispatcher = io,
        log = EngineLog { level, message ->
            log.log(
                when (level) {
                    EngineLog.Level.DEBUG -> LogLevel.DEBUG
                    EngineLog.Level.INFO -> LogLevel.INFO
                    EngineLog.Level.WARN -> LogLevel.WARN
                    EngineLog.Level.ERROR -> LogLevel.ERROR
                },
                "Engine",
                message,
            )
        },
    )

    @Provides @Singleton
    fun settingsRepository(@ApplicationContext context: Context) = SettingsRepository(File(context.filesDir, "settings.json"))

    @Provides @Singleton
    fun presetRepository(@ApplicationContext context: Context) = PresetRepository(File(context.filesDir, "presets.json"))

    @Provides @Singleton
    fun modelRegistry(@ApplicationContext context: Context) =
        ModelRegistry(File(context.filesDir, "models"), OnnxModelValidator(threads = 2))

    @Provides @Singleton
    fun performanceMonitor(@ApplicationContext context: Context) = PerformanceMonitor(context)

    @Provides @Singleton
    fun memoryBudget(monitor: PerformanceMonitor): MemoryBudget = object : MemoryBudget {
        override fun availableBytes(): Long = monitor.availableMemoryBytes()
        override fun isLowRamDevice(): Boolean = monitor.isLowRamDevice()
    }

    @Provides @Singleton
    fun usbAudioInspector(@ApplicationContext context: Context) = UsbAudioInspector(context)
}
