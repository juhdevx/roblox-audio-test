plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.voiceshift.audio"
    compileSdk = libs.versions.compileSdk.get().toInt()
    ndkVersion = libs.versions.ndk.get()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
        consumerProguardFiles("consumer-rules.pro")
        externalNativeBuild {
            cmake {
                // Oboe is distributed as a prefab package that requires the shared C++ runtime.
                arguments += listOf("-DANDROID_STL=c++_shared")
                cppFlags += listOf("-std=c++17", "-Wall", "-Wextra")
            }
        }
        ndk {
            abiFilters += providers.gradleProperty("voiceshift.abis").getOrElse("arm64-v8a").split(",").map { it.trim() }.filter { it.isNotEmpty() }
        }
    }

    buildFeatures {
        prefab = true
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
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
    api(project(":core-dsp"))
    implementation(libs.oboe)
    implementation(libs.androidx.core.ktx)
    implementation(libs.kotlinx.coroutines.android)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
