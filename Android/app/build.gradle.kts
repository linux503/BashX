import com.android.build.gradle.internal.api.BaseVariantOutputImpl
import java.io.File

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

val appVersionCode = 66
val appVersionName = "0.1.66"

android {
    namespace = "com.bashx.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.bashx.app"
        minSdk = 26
        targetSdk = 35
        versionCode = appVersionCode
        versionName = appVersionName
        vectorDrawables.useSupportLibrary = true
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

val mihomoAar = rootProject.file("libs/MihomoCore.aar")

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.10.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material3:material3-window-size-class")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.navigation:navigation-compose:2.8.4")
    implementation("androidx.window:window:1.3.0")
    implementation("androidx.window:window-core:1.3.0")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.yaml:snakeyaml:2.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    debugImplementation("androidx.compose.ui:ui-tooling")
    if (mihomoAar.exists()) {
        implementation(files(mihomoAar))
    }
}

android.applicationVariants.configureEach {
    outputs.configureEach {
        (this as BaseVariantOutputImpl).outputFileName = "BashX-$appVersionName.apk"
    }
}

tasks.configureEach {
    if (name != "assembleDebug" && name != "assembleRelease") return@configureEach
    doLast {
        val flavor = if (name == "assembleRelease") "release" else "debug"
        val src = layout.buildDirectory.file("outputs/apk/$flavor/BashX-$appVersionName.apk").get().asFile
        val dest = rootProject.file("BashX-$appVersionName.apk")
        check(src.exists()) { "Missing APK: $src" }
        src.copyTo(dest, overwrite = true)
        println("Packaged APK: ${dest.absolutePath}")
    }
}

