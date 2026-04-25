import org.jetbrains.kotlin.gradle.plugin.mpp.pm20.util.archivesName

plugins {
  id("org.jetbrains.kotlin.jvm") version "1.9.25"
  `java-library`
}

version = "1.0.0"
archivesName.set("wire-handler")

repositories {
  mavenCentral()
}

dependencies {
  implementation("com.squareup.wire:wire-schema:4.9.11")
}
