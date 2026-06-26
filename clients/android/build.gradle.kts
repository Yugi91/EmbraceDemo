// Top-level build file. Plugin versions declared here, applied in :app.
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Embrace Gradle plugin (9.x) — applied via legacy buildscript classpath because the
        // plugin-marker artifact for `io.embrace.gradle` is published to Maven Central as the
        // `embrace-gradle-plugin` jar. Resolvable from mavenCentral().
        classpath("io.embrace:embrace-gradle-plugin:9.0.0")
    }
}

plugins {
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.3.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.0" apply false
}
