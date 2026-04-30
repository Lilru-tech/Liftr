import java.util.Properties
import java.io.FileInputStream

val localProperties = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) {
        FileInputStream(f).use { load(it) }
    }
}
val keystoreProperties = Properties().apply {
    val f = rootProject.file("keystore.properties")
    if (f.exists()) {
        FileInputStream(f).use { load(it) }
    }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile")?.isNotBlank() == true &&
    keystoreProperties.getProperty("storePassword")?.isNotBlank() == true &&
    keystoreProperties.getProperty("keyAlias")?.isNotBlank() == true &&
    keystoreProperties.getProperty("keyPassword")?.isNotBlank() == true

fun requireQuoted(value: String): String =
    value.replace("\\", "\\\\").replace("\"", "\\\"")

val supabaseUrl: String = localProperties.getProperty("supabase.url", "")
val supabaseKey: String = localProperties.getProperty("supabase.anonKey", "")
/** AdMob banner; en producción, sustituir en `local.properties` (ver `local.properties.example`). */
val adBannerUnitId: String = localProperties.getProperty(
    "admob.bannerId",
    "ca-app-pub-3940256099942544/6300978111"
)
/** Google Maps SDK (cardio: ruta en activo y en detalle). Ver `local.properties.example`. */
val mapsApiKey: String = localProperties.getProperty("maps.apiKey", "")

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.lilru.liftr"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.lilru.liftr"
        minSdk = 26
        targetSdk = 35
        versionCode = 11002
        versionName = "1.10.2"

        buildConfigField("String", "SUPABASE_URL", "\"${requireQuoted(supabaseUrl)}\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"${requireQuoted(supabaseKey)}\"")
        buildConfigField("String", "AD_BANNER_UNIT_ID", "\"${requireQuoted(adBannerUnitId)}\"")
        buildConfigField("String", "MAPS_API_KEY", "\"${requireQuoted(mapsApiKey)}\"")
        manifestPlaceholders["GOOGLE_MAPS_KEY"] = mapsApiKey
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
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
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
    packaging { resources { excludes.add("/META-INF/{AL2.0,LGPL2.1}") } }
    kotlinOptions {
        jvmTarget = "21"
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.10.01")
    implementation(composeBom)
    androidTestImplementation(composeBom)
    // Evita clases duplicadas (p. ej. androidx.activity.ktx.R) al mezclar DEX: ui trae
    // activity-ktx y activity-compose también; una sola copia en el classpath.
    implementation("androidx.compose.ui:ui") {
        exclude(group = "androidx.activity", module = "activity-ktx")
    }
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material:material")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.fragment:fragment:1.8.5")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.navigation:navigation-compose:2.8.4")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    implementation(platform("io.github.jan-tennert.supabase:bom:3.0.2"))
    implementation("io.github.jan-tennert.supabase:postgrest-kt")
    implementation("io.github.jan-tennert.supabase:auth-kt")
    implementation("io.github.jan-tennert.supabase:storage-kt")
    implementation("io.github.jan-tennert.supabase:functions-kt")
    // Obligatorio en Android: motor HTTP de Ktor; sin esto createSupabaseClient() suele lanzar y cerrar la app.
    implementation("io.ktor:ktor-client-android:3.0.1")

    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("androidx.datastore:datastore-preferences:1.1.1")

    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-messaging-ktx")
    implementation("com.google.android.gms:play-services-location:21.3.0")
    implementation("com.google.android.gms:play-services-maps:19.0.0")
    implementation("com.google.maps.android:maps-compose:4.4.1")
    implementation("com.google.android.gms:play-services-ads:23.5.0")
    implementation("com.google.android.ump:user-messaging-platform:3.0.0")
    implementation("com.google.android.play:app-update:2.1.0")
    implementation("com.android.billingclient:billing-ktx:7.1.1")
    implementation("androidx.health.connect:connect-client:1.1.0-alpha10")
    implementation("androidx.glance:glance-appwidget:1.1.0")
    implementation("androidx.glance:glance:1.1.0")
    implementation("androidx.glance:glance-material3:1.1.0")
}

val isReleaseRequested = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}
if (isReleaseRequested && !hasReleaseKeystore) {
    error(
        "Missing release signing config. Create android/keystore.properties from " +
            "android/keystore.properties.example before running release tasks."
    )
}
