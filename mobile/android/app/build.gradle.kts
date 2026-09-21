import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase Cloud Messaging (must come after the Android/Flutter plugins).
    id("com.google.gms.google-services")
}

// Release signing, read from android/key.properties (gitignored, never committed).
//
// This matters more for a sideloaded APK than for the Play Store. Android only installs an update
// over an existing app when both are signed with the SAME key — there is no Play App Signing to
// re-sign for you. The Flutter template signed release builds with the debug key, which lives in
// ~/.android/debug.keystore on whichever machine ran the build: ship one of those and every later
// update has to come from that one laptop, or users must uninstall (losing their local drafts and
// cached chats) to take it.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.livingstone.lc_connect"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Permanent once anyone installs the app: a different id is a different app to Android,
        // so changing it would strand every installed copy. It is also the package registered in
        // google-services.json — the build fails if the two disagree.
        applicationId = "com.livingstone.lc_connect"
        // firebase_messaging 16.x requires Android minSdk >= 23.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // No silent fallback to the debug key: that is exactly the build that cannot be
            // updated later (see keystoreProperties above), so a release without the real key
            // fails here rather than producing an APK that looks fine and is a trap.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                null
            }
        }
    }
}

flutter {
    source = "../.."
}

// Fail a release build up front with instructions, instead of letting Gradle emit an unsigned APK
// that Android refuses to install with an unhelpful "App not installed".
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { it.name.contains("Release") && it.project == project }
    if (buildsRelease && !hasReleaseKey) {
        throw GradleException(
            "Release signing is not configured: android/key.properties is missing.\n" +
                // Android Studio's bundled keytool: a Mac with no system Java has no `keytool`
                // on PATH, and Gradle uses this JDK anyway.
                "1. \"/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool\" " +
                "-genkey -v -keystore ~/lc-connect-release.jks -keyalg RSA " +
                "-keysize 2048 -validity 10000 -alias lc-connect\n" +
                "2. Create android/key.properties with storeFile, storePassword, keyAlias, " +
                "keyPassword.\n" +
                "Back the .jks and its passwords up: lose them and installed copies can " +
                "never be updated."
        )
    }
}
