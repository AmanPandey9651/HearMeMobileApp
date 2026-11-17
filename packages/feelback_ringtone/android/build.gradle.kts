plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    namespace = "com.harto.feelback.ringtone"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    compileOnly("io.flutter:flutter_embedding_release:1.0.0-+")
    implementation("org.jetbrains.kotlin:kotlin-stdlib")
}
