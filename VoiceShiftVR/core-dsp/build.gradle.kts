import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// core-dsp has two halves:
//  * Kotlin (this Gradle module): the voice-parameter model shared by UI, presets and the native bridge.
//  * C++17 (core-dsp/cpp): the portable real-time DSP library. It is compiled by core-audio's CMake for
//    Android and by tests/native/CMakeLists.txt for host unit tests. It has no Android dependencies.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

dependencies {
    implementation(libs.kotlinx.serialization.json)
    testImplementation(libs.junit)
}
