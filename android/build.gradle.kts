import java.io.File
import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

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

fun readManifestPackage(manifestFile: File): String? {
    if (!manifestFile.exists()) return null
    val content = manifestFile.readText()
    return Regex("""package\s*=\s*\"([^\"]+)\"""")
        .find(content)
        ?.groupValues
        ?.getOrNull(1)
}

subprojects {
    pluginManager.withPlugin("com.android.library") {
        val androidExt = extensions.findByName("android") ?: return@withPlugin
        try {
            val getNamespace = androidExt.javaClass.getMethod("getNamespace")
            val setNamespace = androidExt.javaClass.getMethod("setNamespace", String::class.java)
            val currentNamespace = getNamespace.invoke(androidExt) as? String
            if (currentNamespace.isNullOrBlank()) {
                val manifestFile = project.file("src/main/AndroidManifest.xml")
                val fallback = readManifestPackage(manifestFile)
                    ?: "com.example.${project.name.replace('-', '_')}"
                setNamespace.invoke(androidExt, fallback)
            }

            // Some plugins pin compileSdk to 33, but newer AndroidX artifacts require 34+.
            // Override library modules to avoid AAR metadata failures at build time.
            val minCompileSdk = 34
            val getCompileSdk = androidExt.javaClass.methods.firstOrNull { it.name == "getCompileSdk" && it.parameterCount == 0 }
            val setCompileSdk = androidExt.javaClass.methods.firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
            if (getCompileSdk != null && setCompileSdk != null) {
                val currentCompileSdk = (getCompileSdk.invoke(androidExt) as? Int) ?: 0
                if (currentCompileSdk in 1 until minCompileSdk) {
                    setCompileSdk.invoke(androidExt, minCompileSdk)
                }
            } else {
                val getCompileSdkVersion = androidExt.javaClass.methods.firstOrNull { it.name == "getCompileSdkVersion" && it.parameterCount == 0 }
                val setCompileSdkVersion = androidExt.javaClass.methods.firstOrNull { it.name == "setCompileSdkVersion" && it.parameterCount == 1 }
                if (getCompileSdkVersion != null && setCompileSdkVersion != null) {
                    val current = getCompileSdkVersion.invoke(androidExt)?.toString()?.filter { it.isDigit() }?.toIntOrNull() ?: 0
                    if (current in 1 until minCompileSdk) {
                        setCompileSdkVersion.invoke(androidExt, minCompileSdk.toString())
                    }
                }
            }

            // Some older plugins are not aligned with newer AGP/Kotlin defaults.
            // Keep Java/Kotlin targets consistent to avoid JVM target validation failures.
            val getCompileOptions = androidExt.javaClass.getMethod("getCompileOptions")
            val compileOptions = getCompileOptions.invoke(androidExt)
            val setSourceCompatibility = compileOptions.javaClass
                .getMethod("setSourceCompatibility", JavaVersion::class.java)
            val setTargetCompatibility = compileOptions.javaClass
                .getMethod("setTargetCompatibility", JavaVersion::class.java)
            setSourceCompatibility.invoke(compileOptions, JavaVersion.VERSION_17)
            setTargetCompatibility.invoke(compileOptions, JavaVersion.VERSION_17)
        } catch (_: Throwable) {
            // Ignore if this Android plugin version does not expose namespace APIs.
        }
    }

    tasks.withType(JavaCompile::class.java).configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }

    tasks.withType(KotlinCompile::class.java).configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    tasks.withType(JavaCompile::class.java).configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
    tasks.withType(KotlinCompile::class.java).configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
