plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.ghostty.android"
    compileSdk = 35
    ndkVersion = "29.0.14206865"  // Use the version you have installed

    defaultConfig {
        applicationId = "com.ghostty.android"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            // Architectures we support
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isDebuggable = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }

    // Native builds are handled by our custom buildNativeLibs task
    // which uses Makefile to build via Zig, not CMake

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    // Point to our pre-built native libraries
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }
}

dependencies {
    // AndroidX Core
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.activity:activity-compose:1.9.3")

    // Jetpack Compose
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.1")

    // Testing
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation(composeBom)
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")

    // Debug
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}

// Task to build native libraries for all ABIs
tasks.register<Exec>("buildNativeLibs") {
    description = "Build libghostty-vt native libraries for all Android ABIs"
    group = "build"

    workingDir = file("../..")

    // Use wrapper script that handles nix-shell environment
    commandLine("bash", "scripts/gradle-build-native.sh")

    // Configure inputs - track source files
    inputs.files(fileTree("../../android/renderer/src") {
        include("**/*.zig")
        include("**/*.glsl")
    })
    inputs.files(fileTree("../../libghostty-vt") {
        include("**/*.zig")
        exclude("zig-cache/**")
        exclude("zig-out/**")
    })
    inputs.file("../../android/renderer/build.zig")
    inputs.file("../../libghostty-vt/build.zig")

    // Configure outputs - track generated libraries
    outputs.dir("src/main/jniLibs/arm64-v8a")
    outputs.dir("src/main/jniLibs/armeabi-v7a")
    outputs.dir("src/main/jniLibs/x86_64")

    // Set environment variables
    environment("ANDROID_HOME", System.getenv("ANDROID_HOME") ?: "/home/tapan/Android/Sdk")
    environment("ANDROID_NDK_ROOT", System.getenv("ANDROID_NDK_ROOT") ?:
        "${System.getenv("ANDROID_HOME") ?: "/home/tapan/Android/Sdk"}/ndk/29.0.14206865")

    // For debug builds, only build for arm64-v8a to speed up iteration
    // Check if we're building debug variant
    val isDebug = gradle.startParameter.taskNames.any {
        it.contains("Debug", ignoreCase = true) || it.contains("assembleDebug", ignoreCase = true)
    }
    if (isDebug) {
        environment("ANDROID_ABIS", "arm64-v8a")
        println("Building native libs for DEBUG: arm64-v8a only")
    } else {
        println("Building native libs for RELEASE: all ABIs")
    }
}

// Run native build before preBuild
tasks.named("preBuild") {
    dependsOn("buildNativeLibs")
}
