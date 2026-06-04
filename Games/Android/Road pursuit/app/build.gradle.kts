plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.typezero.roadpursuit"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.typezero.roadpursuit"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Pin to JDK 17 — set Android Studio's "Gradle JDK" to 17 as well
    // (Settings > Build Tools > Gradle). The bundled JBR 17 works fine.
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // No external libraries needed — pure framework + Kotlin stdlib.
}
