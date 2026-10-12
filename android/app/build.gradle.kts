import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Optional real release key: android/key.properties (untracked) with
// storeFile/storePassword/keyAlias/keyPassword. Without it, release builds are
// signed with android/app/debug.keystore — the app's one stable signing key.
// It is NOT in git (public repo; **/*.keystore is ignored): it lives in the
// local working copy and the laptop builder copies it into its clones, and
// `tool/build.ps1 release` refuses to build without it. Without that file a
// build would be signed with a different key and could not update installs.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Release channel (set by the laptop builder / tool/build.ps1 release). It is
// only validated here: dev, staging and main are ONE app (same applicationId,
// same label), so any channel's build updates the installed app. The app
// shows the channel next to its version (--dart-define=BUILD_CHANNEL).
// Unset (flutter run, CI tests) = main.
val buildChannel = (System.getenv("BUILD_CHANNEL") ?: "").trim().lowercase()
    .ifEmpty { "main" }
if (buildChannel !in listOf("main", "staging", "dev")) {
    throw GradleException(
        "BUILD_CHANNEL must be main, staging or dev (got '$buildChannel')")
}

android {
    namespace = "com.mfficiency.best_collage"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    defaultConfig {
        applicationId = "com.mfficiency.best_collage"
        manifestPlaceholders["appLabel"] = "BestCollage"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (hasReleaseKeystore) "release" else "debug")
        }
    }
}

flutter {
    source = "../.."
}
