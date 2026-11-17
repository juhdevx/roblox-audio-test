plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

android {
    namespace = "com.voiceshift.vr"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        applicationId = "com.voiceshift.vr"
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 1
        versionName = "0.1.0"
        ndk {
            abiFilters += providers.gradleProperty("voiceshift.abis").getOrElse("arm64-v8a").split(",").map { it.trim() }.filter { it.isNotEmpty() }
        }
    }

    signingConfigs {
        // A fixed, committed debug keystore: every CI build is signed with the same key, so a newer
        // debug APK installs over an older one on the phone without uninstalling first.
        // It is NOT a release key — never use it for store distribution.
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
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        jniLibs {
            // Oboe (via core-audio) and ONNX Runtime may both carry the shared C++ runtime.
            pickFirsts += "**/libc++_shared.so"
            // Compress native libraries inside the APK: a much smaller download for phone sideloading
            // (ONNX Runtime alone is ~36 MB uncompressed per ABI).
            useLegacyPackaging = true
        }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
        // Robolectric smoke test renders the real Compose UI and needs merged resources.
        unitTests.isIncludeAndroidResources = true
    }
}

tasks.withType<Test>().configureEach {
    // Opt-in screenshot capture: ./gradlew :app-android:testDebugUnitTest -Pvoiceshift.screenshots=true
    systemProperty("voiceshift.screenshots", providers.gradleProperty("voiceshift.screenshots").getOrElse("false"))
}

dependencies {
    implementation(project(":core-dsp"))
    implementation(project(":core-audio"))
    implementation(project(":core-models"))
    implementation(project(":core-inference"))
    implementation(project(":bridge-usb"))
    implementation(project(":bridge-network"))
    implementation(project(":diagnostics"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.service)

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.core)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)

    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.androidx.hilt.lifecycle.viewmodel.compose)

    implementation(libs.kotlinx.coroutines.android)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.ext.junit)
    testImplementation(platform(libs.compose.bom))
    testImplementation(libs.compose.ui.test.junit4)
    testImplementation(libs.hilt.android.testing)
    kspTest(libs.hilt.compiler)
    debugImplementation(libs.compose.ui.test.manifest)
}
