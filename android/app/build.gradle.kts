import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing details live in android/key.properties, which is deliberately
// not in version control — see README. When it is absent (a fresh clone, or CI)
// the release build falls back to the debug key, so `flutter run --release`
// still works without any setup. Only a build that finds this file produces an
// artifact that is publishable.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

android {
    namespace = "io.github.lepenguin22.ticker"
    // Pinned rather than taking flutter.compileSdkVersion:
    // flutter_local_notifications requires 35 as a minimum.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications relies on core library desugaring, and
        // requires it even for apps that only post immediate notifications.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.lepenguin22.ticker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Carried into the manifest so a build that is not the real one can
        // say so on the home screen.
        manifestPlaceholders["appLabel"] = "Portfolio Alerts"
    }

    signingConfigs {
        // Declared only when the properties file is present: a half-populated
        // config would fail the build for anyone who just wants a debug APK.
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")

            // A release build without the keystore is signed with the debug
            // key, and Android will not let it replace an app signed with the
            // real one — installing over it fails outright. Giving it its own
            // application id makes it a separate app instead, so a CI build
            // can be installed alongside the real one for testing without
            // uninstalling anything or losing its data.
            //
            // The label changes with it: two apps sharing an icon and a name
            // would leave no way to tell which is which on the home screen.
            if (!hasReleaseKeystore) {
                applicationIdSuffix = ".ci"
                manifestPlaceholders["appLabel"] = "Portfolio Alerts CI"
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
