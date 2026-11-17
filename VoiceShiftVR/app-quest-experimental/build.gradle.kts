// EXPERIMENTAL research APK for Meta Quest (Route B / Route C). It does not and cannot create a
// system microphone for other apps; see docs/QUEST_BRIDGE.md.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.voiceshift.quest.lab"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        applicationId = "com.voiceshift.quest.lab"
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 1
        versionName = "0.1.0-experimental"
        ndk {
            abiFilters += providers.gradleProperty("voiceshift.abis").getOrElse("arm64-v8a").split(",").map { it.trim() }.filter { it.isNotEmpty() }
        }
    }

    signingConfigs {
        getByName("debug") {
            storeFile = rootProject.file("keystore/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    packaging {
        jniLibs {
            pickFirsts += "**/libc++_shared.so"
            // Compress native libraries inside the APK: a much smaller download for phone sideloading
            // (ONNX Runtime alone is ~36 MB uncompressed per ABI).
            useLegacyPackaging = true
        }
    }
}

dependencies {
    implementation(project(":core-dsp"))
    implementation(project(":core-audio"))
    implementation(project(":bridge-network"))
    implementation(project(":diagnostics"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.kotlinx.coroutines.android)
}
