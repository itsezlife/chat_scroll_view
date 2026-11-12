group = "dev.chatscrollview.frame_texture"
version = "0.1.0"

buildscript {
    val kotlinVersion = "2.2.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    namespace = "dev.chatscrollview.frame_texture"

    compileSdk = 36

    // The pinned Flutter's default NDK (flutter.ndkVersion), which the app
    // builds with: a plugin may not ask for a higher one than its app. NDK
    // r28 also aligns to 16 KB pages by default (ADR 042).
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    // libframe_texture.so: the texture table the render workers lock and
    // post through, and its JNI side.
    externalNativeBuild {
        cmake {
            path = file("CMakeLists.txt")
        }
    }

    defaultConfig {
        minSdk = 24
    }
}
