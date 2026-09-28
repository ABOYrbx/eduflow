pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        id("com.android.application") version "8.13.2"
        id("org.jetbrains.kotlin.android") version "1.9.24"
        id("org.jetbrains.kotlin.plugin.serialization") version "1.9.24"
        id("org.jetbrains.kotlin.plugin.compose") version "1.9.24"
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "EduFlow"
include(":app")
