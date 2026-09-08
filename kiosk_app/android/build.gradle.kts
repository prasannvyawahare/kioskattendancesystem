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

// Several Flutter plugins ship a build.gradle whose Kotlin compile tasks
// inherit a default JVM target (21, from whatever JDK Gradle runs on) that
// doesn't match that same plugin's own Java compileOptions -- Gradle
// refuses to build when a module's Java and Kotlin tasks disagree.
// Different plugins disagree in different directions (tflite_flutter's own
// Java side is 1.8; camera_android_camerax's is 17), so there's no single
// value that fixes all of them -- instead, read each plugin's own existing
// Java targetCompatibility and point its Kotlin compile at that same
// value, per module. Our own "app" module is excluded -- it already sets a
// consistent 17/17 itself in android/app/build.gradle.kts.
//
// Deliberately NOT touching JavaCompile tasks: doing that (even just
// source/targetCompatibility) previously broke AGP's own classpath wiring
// for other plugins (flutter_secure_storage failed to resolve android.*
// packages) -- leaving JavaCompile alone avoids that entirely.
//
// This has to run inside `gradle.projectsEvaluated`, not a plain
// `subprojects { ... }` block: KGP registers its own default jvmTarget from
// inside each plugin module's own build.gradle, which evaluates *after*
// this root build.gradle -- a same-timing override here gets silently
// overwritten again by KGP's later one. projectsEvaluated runs only once
// every project (including every plugin module) has fully finished
// configuring itself, so this genuinely runs last.
gradle.projectsEvaluated {
    subprojects {
        if (name == "app") return@subprojects
        val androidExt = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        val targetCompat = androidExt?.compileOptions?.targetCompatibility ?: JavaVersion.VERSION_1_8
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile> {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(targetCompat.toString()))
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
