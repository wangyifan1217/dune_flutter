import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // 不使用 com.huawei.agconnect 插件：与当前 AGP 9 / Flutter 插件 DSL 不兼容。
    // 华为 AppId 通过 AndroidManifest meta-data + agconnect-services.json 生效。
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

fun localProp(key: String, fallback: String): String =
    localProperties.getProperty(key)?.trim()?.takeIf { it.isNotEmpty() } ?: fallback

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

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

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        debug {
            // 厂商通道（华为等）要求正式签名；有 keystore 时 debug 也用同一把钥匙。
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        release {
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
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
    // 华为厂商通道：版本与主 SDK 同系列；需配合 app/agconnect-services.json
    implementation("com.tencent.tpns:huawei:1.4.4.6-release")
    implementation("com.huawei.hms:push:6.12.0.300")
    implementation("me.leolin:ShortcutBadger:1.1.22@aar")
}
