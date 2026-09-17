allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    afterEvaluate {
        if (extensions.findByName("android") != null) {
            val android = extensions.getByName("android")
            val current = try {
                android.javaClass.getMethod("getCompileSdkVersion")
                    .invoke(android) as? String
            } catch (_: Exception) { null }

            val version = current?.removePrefix("android-")?.toIntOrNull()
            if (version == null || version < 36) {
                logger.warn("Forcing compileSdk 36 for ${project.name} (was $current)")
                android.javaClass.getMethod("compileSdkVersion", Int::class.java)
                    .invoke(android, 36)
            }
        }
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
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
