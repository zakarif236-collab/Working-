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
