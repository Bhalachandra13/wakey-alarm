import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. Reads android/key.properties (gitignored)
// so the upload keystore + passwords never enter the repo.
// See docs/play-store-publish.md for the generation steps
// and the backup reminder (losing the .jks file means you
// can never update the app on the Play Store).
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
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

        // Manifest placeholder values. The Maps API key is
        // read from android/local.properties (gitignored) so
        // the open-source repo doesn't ship a secret. Without
        // a real key the map widget shows a blank canvas but
        // the rest of the geofence feature still works (the
        // picker falls back to lat/long + Nominatim search).
        // See docs/play-store-publish.md for how to provision
        // a real key in Google Cloud Console.
        //
        // We have to read local.properties explicitly: gradle
        // does not surface its entries via `project.findProperty`,
        // so without this block the placeholder would silently
        // fall back to "DEV_NO_KEY" and the map would render blank.
        val localProps = Properties()
        val localPropsFile = rootProject.file("local.properties")
        if (localPropsFile.exists()) {
            localPropsFile.inputStream().use { localProps.load(it) }
        }
        manifestPlaceholders["MAPS_API_KEY"] =
            localProps.getProperty("MAPS_API_KEY") ?: "DEV_NO_KEY"
    }

    signingConfigs {
        create("release") {
            // The upload keystore. Backing this up is the
            // single most important thing in the release
            // pipeline — without it, you cannot push updates.
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")
                ?.let { rootProject.file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            // Sign with the upload keystore so the produced
            // AAB is accepted by Play Console. (Previously signed
            // with the debug key, which Play Console rejects.)
            signingConfig = signingConfigs.getByName("release")
            // R8 full mode strips unused Java/Kotlin classes and obfuscates
            // the rest. Combined with resource shrinking this typically
            // halves the APK and noticeably speeds up dexing/linking
            // because there's less code to process.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Per-ABI APK splits were previously enabled here so direct
    // sideloaders (outside the Play Store) could grab a lean
    // APK for their architecture. Play Store distribution uses
    // the AAB (`flutter build appbundle`), which Google splits
    // per-ABI internally — and Android's bundletool rejects
    // building an AAB when `splits.abi` is also enabled (the
    // "Multiple shrunk-resources files" error from
    // https://issuetracker.google.com/402800800).
    //
    // Since the publish target is the Play Store, the splits
    // block is removed. If a lean per-ABI APK is needed for
    // sideloading, use `flutter build apk --split-per-abi`
    // which enables the splits on the APK build path only.
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
