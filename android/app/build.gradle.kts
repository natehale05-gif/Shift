import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key, when there is one.
//
// `android/key.properties` is written by CI from repository secrets and is
// git-ignored — a keystore in version control is a keystore anyone with read
// access can publish updates with.
//
// When the file is absent (any local build, and CI without the secrets set),
// the release build falls back to the debug key. That produces an installable
// APK for testing and **cannot be uploaded to Google Play**, which rejects
// anything signed with the debug key. That is the correct failure: a local
// build that quietly produced a Play-shaped artifact would be worse.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasUploadKey = keystoreProperties.containsKey("storeFile")

android {
    namespace = "club.shiftai.shift"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "club.shiftai.shift"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
            // No R8 minification. It was enabled here in the first draft and
            // failed to compile in CI; more to the point it should not have
            // been enabled at all. A Flutter app's Java/Kotlin surface is a
            // thin shim around AOT-compiled Dart, so shrinking it saves very
            // little — and Flutter's own template leaves it off for that
            // reason. Trading a working build for a marginal size win is a bad
            // trade; revisit only if the bundle is measured and found wanting.
        }
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
