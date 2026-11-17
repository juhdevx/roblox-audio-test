pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "VoiceShiftVR"

// Applications
include(":app-android")
include(":app-quest-experimental")

// Core libraries
include(":core-dsp")        // Pure Kotlin parameter model + portable C++17 DSP sources (core-dsp/cpp)
include(":core-audio")      // Oboe/AAudio engine (C++ + JNI) and Kotlin engine controller
include(":core-models")     // Presets, model registry, JSON persistence (pure Kotlin)
include(":core-inference")  // ONNX Runtime backend, model inspection, streaming worker

// Bridges and tooling
include(":bridge-usb")      // Route A: USB/wired output discovery and diagnostics
include(":bridge-network")  // Route C: experimental LAN PCM streaming
include(":diagnostics")     // Logs, CPU/memory/thermal monitoring, reports
