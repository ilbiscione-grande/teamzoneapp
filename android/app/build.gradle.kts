import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The Play upload key lives outside git: android/key.properties points to
// the keystore (see docs/operations/android_release.md). Without it, local
// and audit release builds fall back to the debug key, and a Play bundle
// (bundleRelease) refuses to build.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasUploadKey = keystorePropertiesFile.exists()

// Firebase is shared by test and production, so they are separate Android
// apps: only a TEAMZONE_ENV=production build is com.teamzone.teamzone; every
// other build (audit, local) is com.teamzone.teamzone.test, labelled
// "TeamZone Test", and reports to its own Crashlytics and FCM app. Flutter
// passes the --dart-define values base64-encoded in "dart-defines".
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.filter { it.isNotBlank() }
        ?.map { String(Base64.getDecoder().decode(it)) }
        ?.associate { it.substringBefore("=") to it.substringAfter("=", "") }
        ?: emptyMap()
val isProductionBuild = dartDefines["TEAMZONE_ENV"] == "production"

android {
    namespace = "com.teamzone.teamzone"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId =
            if (isProductionBuild) "com.teamzone.teamzone" else "com.teamzone.teamzone.test"
        manifestPlaceholders["appLabel"] = if (isProductionBuild) "TeamZone" else "TeamZone Test"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasUploadKey) signingConfigs.getByName("upload")
                else signingConfigs.getByName("debug")
            // R8 shrinks and optimizes the Android (Java/Kotlin) side; the
            // Crashlytics plugin uploads its mapping file. Dart code is not
            // obfuscated, so crash stacks stay readable (see xobs_policy.md).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// A bundle for Google Play must never be signed with the debug key, and is
// always the production app.
gradle.taskGraph.whenReady {
    if (allTasks.none { it.name == "bundleRelease" }) return@whenReady
    if (!hasUploadKey) {
        throw GradleException(
            "android/key.properties is missing: a Play bundle needs the upload key " +
                "(docs/operations/android_release.md).",
        )
    }
    if (!isProductionBuild) {
        throw GradleException(
            "A Play bundle must be built with --dart-define=TEAMZONE_ENV=production " +
                "(docs/operations/android_release.md).",
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
