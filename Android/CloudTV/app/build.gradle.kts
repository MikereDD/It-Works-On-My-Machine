plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.typezero.cloudtv"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.typezero.cloudtv"
        minSdk = 26
        targetSdk = 34
        versionCode = 4
        versionName = "0.4.0"

        // Ship 64-bit and 32-bit ARM native libs. arm64-v8a covers modern phones
        // and most Android TVs; armeabi-v7a is REQUIRED for Chromecast with Google
        // TV (4K and HD) and other 32-bit ARM TV devices — without it the APK fails
        // to install on those with "no matching ABI".
        // (x86_64 is omitted, so a standard emulator still needs this commented out.)
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }

        // --- Google Drive OAuth (AppAuth) -------------------------------------
        // REPLACE the two placeholders below with YOUR Android OAuth client ID
        // from Google Cloud Console. The id looks like:
        //   1234567890-abc123.apps.googleusercontent.com
        // The redirect scheme is that SAME id with the domain reversed off:
        //   com.googleusercontent.apps.1234567890-abc123
        buildConfigField(
            "String",
            "GOOGLE_CLIENT_ID",
            "\"REPLACE_ME.apps.googleusercontent.com\""
        )
        manifestPlaceholders["appAuthRedirectScheme"] =
            "com.googleusercontent.apps.REPLACE_ME"
        // ----------------------------------------------------------------------

        // --- OneDrive OAuth (Microsoft Graph) ---------------------------------
        // REPLACE with YOUR Application (client) ID from the Entra app
        // registration (Personal + work/school accounts).
        buildConfigField(
            "String",
            "MICROSOFT_CLIENT_ID",
            "\"REPLACE_ME_MS_CLIENT_ID\""
        )
        // ----------------------------------------------------------------------
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

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.10"
    }
    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.02.00")
    implementation(composeBom)

    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.7.0")

    // Jetpack Compose (works on Android TV with D-pad focus handling)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")

    // VLC (LibVLC) engine for audio + video playback — wide codec support
    implementation("org.videolan.android:libvlc-all:3.6.0")

    // Networking
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Google OAuth (auth-code + PKCE via Chrome Custom Tabs) for Google Drive.
    // Google blocks OAuth in embedded WebViews, so Drive sign-in uses AppAuth.
    implementation("net.openid:appauth:0.11.1")

    // Async image loading for folder/poster thumbnails (v2.8.2)
    implementation("io.coil-kt:coil-compose:2.6.0")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // Google Cast (Chromecast) — phone casts the resolved stream URL to the TV.
    // Only used when a Cast session is active; local LibVLC playback is unaffected.
    implementation("com.google.android.gms:play-services-cast-framework:21.4.0")
    implementation("androidx.mediarouter:mediarouter:1.6.0")
    implementation("androidx.appcompat:appcompat:1.6.1")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
