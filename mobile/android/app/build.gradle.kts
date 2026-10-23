import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties names the keystore (kept outside the repo). Without it, the debug key.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "app.nutrimeter"
    compileSdk = flutter.compileSdkVersion
    // CI names the NDK and CMake its runner image already ships (ciNdkVersion, ciCmakeVersion) instead of
    // downloading Flutter's defaults on every build. The NDK only strips prebuilt libraries, so the APK is identical.
    ndkVersion = providers.gradleProperty("ciNdkVersion").getOrElse(flutter.ndkVersion)
    providers.gradleProperty("ciCmakeVersion").orNull?.let { externalNativeBuild { cmake { version = it } } }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        buildConfig = true   // BuildConfig.FLAVOR, read by the updater to pick its APK
    }

    defaultConfig {
        applicationId = "app.nutrimeter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "env"
    productFlavors {
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "Nutrimeter")
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "Nutrimeter Staging")
        }
    }

    signingConfigs {
        if (keyProps.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keyProps["storeFile"] as String)
                storePassword = keyProps["storePassword"] as String
                keyAlias = keyProps["keyAlias"] as String
                keyPassword = keyProps["keyPassword"] as String
            }
        }
    }

    buildTypes {
        // Debug builds install beside the release ones (different key, lower version code), so a dev
        // loop on a real phone never uninstalls the installed app and its data.
        debug {
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "Nutrimeter Dev")
        }
        release {
            signingConfig = if (keyProps.containsKey("storeFile")) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
