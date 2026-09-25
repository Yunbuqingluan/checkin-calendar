allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
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

// 强制所有 Android 子项目（含插件）使用 compileSdk 36
subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                android.javaClass
                    .getMethod("setCompileSdkVersion", Int::class.java)
                    .invoke(android, 36)
            } catch (_: Exception) {}
        }
    }
    plugins.withId("com.android.application") {
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                android.javaClass
                    .getMethod("setCompileSdkVersion", Int::class.java)
                    .invoke(android, 36)
            } catch (_: Exception) {}
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}