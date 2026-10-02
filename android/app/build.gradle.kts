plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("org.jetbrains.kotlin.plugin.compose")
}

// ---------------------------------------------------------------------------
// Release-Signatur (nur Umgebung, nie Datei im Repo)
// ---------------------------------------------------------------------------
// Der Keystore kommt als GitHub Secret (base64) bzw. aus der lokalen Shell.
// Pflichtnamen, siehe .github/RELEASING.md:
//   EDUFLOW_KEYSTORE_PATH, EDUFLOW_KEYSTORE_PASSWORD,
//   EDUFLOW_KEY_ALIAS, EDUFLOW_KEY_PASSWORD
// Ohne Keystore nutzt der Release-Build den Debug-Key, damit `assembleRelease`
// auch ohne Secrets baubar bleibt. Der Release-Workflow setzt zusätzlich
// -PeduflowRequireReleaseSigning=true und bricht dann hart ab, statt
// versehentlich einen debug-signierten APK zu veroeffentlichen.
val keystorePath = providers.environmentVariable("EDUFLOW_KEYSTORE_PATH").orNull
    ?.trim()
    ?.takeIf { it.isNotEmpty() && file(it).exists() }
// Der Keystore ist PKCS12, und PKCS12 kennt kein getrenntes Key-Passwort:
// keytool ignoriert -keypass mit einer Warnung. Deshalb reicht das
// Store-Passwort; EDUFLOW_KEY_PASSWORD wird nur gelesen, falls künftig
// auf JKS umgestellt wird (dort sind zwei Passwörter nötig).
val hasReleaseKeystore = keystorePath != null
val requireReleaseSigning =
    providers.gradleProperty("eduflowRequireReleaseSigning").orNull == "true"

if (requireReleaseSigning && !hasReleaseKeystore) {
    throw GradleException(
        "Release-Signatur ist Pflicht, aber es ist kein Keystore hinterlegt. " +
            "EDUFLOW_KEYSTORE_PATH (plus Passwort/Alias) setzen oder " +
            "-PeduflowRequireReleaseSigning weglassen."
    )
}

// Versions_override aus der CI: der Release-Workflow liest die VERSION-Datei
// im Repo-Root und injiziert sie hier, damit APK und Tag nicht auseinanderlaufen.
val versionNameOverride =
    (providers.gradleProperty("eduflowVersionName").orNull ?: "").trim()
val versionCodeOverride =
    (providers.gradleProperty("eduflowVersionCode").orNull ?: "").trim()

android {
    namespace = "de.eduflow.android"
    compileSdk = 34

    defaultConfig {
        applicationId = "de.eduflow.android"
        minSdk = 26
        targetSdk = 34
        versionCode = versionCodeOverride.toIntOrNull() ?: 1
        versionName = versionNameOverride.ifEmpty { "0.1.0" }
        vectorDrawables { useSupportLibrary = true }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystorePath!!)
                storePassword = providers.environmentVariable("EDUFLOW_KEYSTORE_PASSWORD").orNull
                keyAlias = providers.environmentVariable("EDUFLOW_KEY_ALIAS").orNull
                keyPassword = providers.environmentVariable("EDUFLOW_KEY_PASSWORD")
                    .orElse(providers.environmentVariable("EDUFLOW_KEYSTORE_PASSWORD"))
                    .orNull
            }
        }
    }

    buildTypes {
        release {
            // Absichtlich keine ABI-Splits: assembleRelease erzeugt genau eine
            // universelle APK, die auf jedem Geraet per Sideload laeuft.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.06.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.7.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.7.0")
    implementation("androidx.navigation:navigation-compose:2.7.7")
    implementation("androidx.datastore:datastore-preferences:1.1.1")

    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    // Nur für Pull-to-Refresh auf der Übersicht (BOM-verwaltete Version).
    implementation("androidx.compose.material:material")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")

    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.retrofit2:converter-kotlinx-serialization:2.11.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
}
