plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.voiceshift.inference"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    api(project(":core-models"))
    implementation(libs.onnxruntime.android)
    implementation(libs.kotlinx.coroutines.android)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    // The desktop ONNX Runtime jar exposes the identical ai.onnxruntime API and ships Linux/macOS/Windows
    // native libraries, so JVM unit tests can execute real .onnx files (see src/test/resources).
    testImplementation(libs.onnxruntime.jvm)
}

// The Android AAR's native library cannot load on the JVM test host; swap it for the desktop jar.
configurations.configureEach {
    if (name.endsWith("UnitTestRuntimeClasspath")) {
        exclude(group = "com.microsoft.onnxruntime", module = "onnxruntime-android")
    }
}
