plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Apply the Embrace Gradle plugin only for the `embrace` arm. We select the arm with a Gradle
// property: `-PtelemetryTool=embrace` (default) or `-PtelemetryTool=otel`. The plain-OTel arm
// must NOT apply the Embrace plugin (it would inject the SDK init / bytecode).
val telemetryTool: String = (project.findProperty("telemetryTool") as String?) ?: "embrace"
if (telemetryTool == "embrace") {
    // Plugin id registered by io.embrace:embrace-gradle-plugin
    apply(plugin = "io.embrace.gradle")
}

android {
    namespace = "io.embrace.demo.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.embrace.demo.android"
        minSdk = 21          // FnB constraint
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0+1"

        // Selected telemetry arm, surfaced to app code.
        buildConfigField("String", "TELEMETRY_TOOL", "\"$telemetryTool\"")
        // OTLP collector reachable from inside the emulator (host loopback = 10.0.2.2).
        buildConfigField("String", "OTLP_HTTP_ENDPOINT", "\"http://10.0.2.2:4318\"")
        // When true, MainActivity auto-fires demo actions for headless verification.
        val autofire = (project.findProperty("autofire") as String?) ?: "false"
        buildConfigField("boolean", "AUTOFIRE", autofire)
    }

    buildTypes {
        debug {
            isMinifyEnabled = false   // debug = NOT minified (relevant to E2 symbolication)
            applicationIdSuffix = ""
        }
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    // (Kotlin jvmTarget set via the top-level kotlin {} compilerOptions DSL below —
    //  Kotlin 2.3.0 removed the kotlinOptions.jvmTarget String setter.)
    buildFeatures {
        compose = true
        buildConfig = true
    }
    // minSdk 21 + OkHttp 4 (pulled by the OTLP exporter) require core library desugaring for
    // java.time/java.util used on API < 26.
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "/META-INF/INDEX.LIST"
            excludes += "/META-INF/io.netty.versions.properties"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.10.01")
    implementation(composeBom)
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.foundation:foundation")

    // ---- Embrace Android SDK + its OTel-Kotlin exporter ----
    // On BOTH arms now: the project compiles with Kotlin 2.3.0, so the kotlin-stdlib 2.3.0 these
    // drag in no longer conflicts. This lets the demo route custom spans through Embrace's TracingApi
    // (Embrace.getInstance().recordCompletedSpan) in the embrace arm so they reach the Embrace cloud
    // dashboard (not just Grafana). The embrace gradle PLUGIN is still applied only for the embrace arm.
    implementation("io.embrace:embrace-android-sdk:9.0.0")
    implementation("io.opentelemetry.kotlin:exporters-otlp:0.4.0")
    implementation("io.opentelemetry.kotlin:sdk-api:0.4.0")

    // ---- OpenTelemetry-Java: the plain-OTel arm (telemetry.tool=otel), the F1 baseline ----
    // Standard OTel Java SDK + OTLP/HTTP exporter, no Embrace code in this arm.
    implementation(platform("io.opentelemetry:opentelemetry-bom:1.45.0"))
    implementation("io.opentelemetry:opentelemetry-api")
    implementation("io.opentelemetry:opentelemetry-sdk")
    implementation("io.opentelemetry:opentelemetry-exporter-otlp")
    implementation("io.opentelemetry.semconv:opentelemetry-semconv:1.28.0-alpha")

    // OkHttp backs the OTLP/HTTP sender used by the Java exporter.
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.2")
}
