import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

fun localProp(key: String, fallback: String): String =
    localProperties.getProperty(key)?.trim()?.takeIf { it.isNotEmpty() } ?: fallback

android {
    namespace = "nova.dunes.dunes_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "nova.dunes.dunes_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 腾讯云 TPNS：在 android/local.properties 配置 tpns.accessId / tpns.accessKey。
        // run-android.ps1 会自动读取并注入 --dart-define。
        manifestPlaceholders["XG_ACCESS_ID"] =
            localProp("tpns.accessId", "your_tpns_access_id")
        manifestPlaceholders["XG_ACCESS_KEY"] =
            localProp("tpns.accessKey", "your_tpns_access_key")
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.tencent.tpns:tpns:1.4.4.6-release")
    implementation("me.leolin:ShortcutBadger:1.1.22@aar")
}
