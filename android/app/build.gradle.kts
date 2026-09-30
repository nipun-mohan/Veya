import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeys = Properties()
val releaseKeysFile = rootProject.file("key.properties")
if (releaseKeysFile.exists()) releaseKeys.load(FileInputStream(releaseKeysFile))

android {
    namespace = "app.veya.veya"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    flavorDimensions += "experience"
    productFlavors {
        create("standard") { dimension = "experience" }
        create("assistant") { dimension = "experience" }
    }

    // Closed testing and Play releases use the standard flavor. It must carry
    // the same accessibility service and bridge as the assistant flavor.
    sourceSets {
        getByName("standard") {
            java.setSrcDirs(listOf("src/assistant/kotlin"))
            res.setSrcDirs(listOf("src/assistant/res"))
            manifest.srcFile("src/assistant/AndroidManifest.xml")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.veya.veya"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeysFile.exists()) {
            create("upload") {
                keyAlias = releaseKeys.getProperty("keyAlias")
                keyPassword = releaseKeys.getProperty("keyPassword")
                storeFile = rootProject.file(releaseKeys.getProperty("storeFile"))
                storePassword = releaseKeys.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Keep the install build quick and predictable; publishing can enable
            // shrinking once the release pipeline is finalized.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles("proguard-rules.pro")
            // Development fallback; provide key.properties for publishing.
            signingConfig = signingConfigs.getByName(if (releaseKeysFile.exists()) "upload" else "debug")
        }
    }

    lint {
        checkReleaseBuilds = false
    }
}

flutter {
    source = "../.."
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation("androidx.core:core-splashscreen:1.0.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.android.gms:play-services-auth-api-phone:18.1.0")
    implementation("com.google.firebase:firebase-auth:23.2.1")
}
