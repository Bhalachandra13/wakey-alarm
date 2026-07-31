import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.wakeywakey.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.wakeywakey.app"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Manifest placeholder values. The Maps API key is intentionally
        // left as a placeholder so the open-source repo doesn't ship a
        // secret; without a real key the map widget shows a blank canvas
        // but the rest of the geofence feature still works. Set
        // MAPS_API_KEY in android/local.properties (or your CI secrets)
        // to a real Google Maps API key to enable tile rendering.
        //
        // We have to read local.properties explicitly: gradle does not
        // surface its entries via `project.findProperty`, so without
        // this block the placeholder would silently fall back to
        // "DEV_NO_KEY" and the map would render blank.
        val localProps = Properties()
        val localPropsFile = rootProject.file("local.properties")
        if (localPropsFile.exists()) {
            localPropsFile.inputStream().use { localProps.load(it) }
        }
        manifestPlaceholders["MAPS_API_KEY"] =
            localProps.getProperty("MAPS_API_KEY") ?: "DEV_NO_KEY"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    // Google Play Services Location: provides GeofencingClient,
    // FusedLocationProviderClient, and Priority constants used by
    // GeofenceController.kt and GeofenceTransitionReceiver.kt.
    // Version pinned to match the rest of the play-services-* family
    // transitively pulled in by google_maps_flutter.
    implementation("com.google.android.gms:play-services-location:21.3.0")
}
