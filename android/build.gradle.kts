allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
    project.plugins.whenPluginAdded {
        if (this is com.android.build.gradle.LibraryPlugin) {
            project.extensions.configure<com.android.build.gradle.LibraryExtension> {
                if (namespace == null || namespace!!.isEmpty()) {
                    val manifest = project.file("src/main/AndroidManifest.xml")
                    if (manifest.exists()) {
                        val pkg = Regex("package=\"([^\"]+)\"").find(manifest.readText())?.groupValues?.get(1)
                        if (pkg != null) namespace = pkg
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
