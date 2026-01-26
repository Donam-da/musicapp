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
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    if (project.name == "on_audio_query_android") {
        val fixConfig = {
            project.extensions.findByName("android")?.let { android ->
                android.javaClass.getMethod("setNamespace", String::class.java).invoke(android, "com.lucasjosino.on_audio_query")

                // Ép buộc sử dụng Java 17 để đồng bộ với app và loại bỏ cảnh báo obsolete
                val compileOptions = android.javaClass.getMethod("getCompileOptions").invoke(android)
                val javaVersion = org.gradle.api.JavaVersion.VERSION_17
                compileOptions.javaClass.getMethod("setSourceCompatibility", org.gradle.api.JavaVersion::class.java).invoke(compileOptions, javaVersion)
                compileOptions.javaClass.getMethod("setTargetCompatibility", org.gradle.api.JavaVersion::class.java).invoke(compileOptions, javaVersion)
            }
            project.tasks.configureEach {
                try {
                    val kotlinOptions = this.javaClass.getMethod("getKotlinOptions").invoke(this)
                    kotlinOptions.javaClass.getMethod("setJvmTarget", String::class.java).invoke(kotlinOptions, "17")
                } catch (e: Exception) { }
            }
        }
        if (project.state.executed) {
            fixConfig()
        } else {
            project.afterEvaluate { fixConfig() }
        }
    }
}
