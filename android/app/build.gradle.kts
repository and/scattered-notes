plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.scatterednotes"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.scatterednotes.android"
        minSdk = 26
        targetSdk = 36
        // Same version as the Mac and Windows apps; versionCode follows the Mac app's CFBundleVersion
        versionCode = 8
        versionName = "1.1.5"
    }

    // The release key stays outside the repo. scripts/release-android.sh passes its path and password in;
    // without them release builds are left unsigned
    val keystore = System.getenv("SN_ANDROID_KEYSTORE")
    signingConfigs {
        create("release") {
            if (keystore != null) {
                storeFile = file(keystore)
                storePassword = System.getenv("SN_ANDROID_KEYSTORE_PASSWORD")
                keyAlias = "scattered-notes"
                keyPassword = System.getenv("SN_ANDROID_KEYSTORE_PASSWORD")
            }
        }
    }

    // Both builds have the same app ID and key, so either can update the other
    flavorDimensions += "store"
    productFlavors {
        // The APK attached to GitHub releases, which checks GitHub for updates
        create("github") {
            dimension = "store"
            buildConfigField("boolean", "UPDATES_FROM_GITHUB", "true")
        }
        // Google Play updates the app itself and doesn't allow apps to update themselves
        create("play") {
            dimension = "store"
            buildConfigField("boolean", "UPDATES_FROM_GITHUB", "false")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            if (keystore != null) signingConfig = signingConfigs.getByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.07.00")
    implementation(composeBom)
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.2")
    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
    // Android's org.json is a stub in local unit tests
    testImplementation("org.json:json:20240303")
}
