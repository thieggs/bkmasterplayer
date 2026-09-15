import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Assinatura do release: android/key.properties (fora do git) aponta para o
// keystore. Sem ele, assina com a chave de debug (instala, mas não atualiza por
// cima de um APK assinado com a chave de release, e vice-versa).
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// ABIs deste build (flutter build apk --target-platform ...; sem ela, as três).
val abiTriples = mapOf(
    "android-arm64" to ("arm64-v8a" to "aarch64-linux-android"),
    "android-arm" to ("armeabi-v7a" to "arm-linux-androideabi"),
    "android-x64" to ("x86_64" to "x86_64-linux-android"),
)
val targetPlatforms = (project.findProperty("target-platform") as String?)
    ?.split(",")?.map { it.trim() }?.filter { it in abiTriples }
    ?.takeIf { it.isNotEmpty() } ?: abiTriples.keys.toList()

android {
    namespace = "io.github.playermusica.player_musica"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "io.github.playermusica.player_musica"
        // Android 8.0+: o áudio sai pela AAudio (cpal), que começa na API 26.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Só as ABIs pedidas: alguns plugins trazem bibliotecas prontas de todas.
        ndk { abiFilters += targetPlatforms.map { abiTriples.getValue(it).first } }
    }

    signingConfigs {
        if (!keyProps.isEmpty) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (keyProps.isEmpty) "debug" else "release")
        }
        // O plugin do Flutter põe as 3 ABIs padrão em cada buildType, e o
        // Android junta com as do defaultConfig: sem trocar aqui, as bibliotecas
        // de plugins em x86_64/armv7 entravam no APK "só arm64" e um aparelho
        // x86_64 escolhia essa ABI, sem o motor, e fechava na abertura.
        configureEach {
            ndk {
                abiFilters.clear()
                abiFilters += targetPlatforms.map { abiTriples.getValue(it).first }
            }
        }
    }

    sourceSets["main"].jniLibs.srcDir(layout.buildDirectory.dir("cxx-shared"))
    packaging {
        jniLibs.pickFirsts += "**/libc++_shared.so"
        // Bibliotecas nativas comprimidas no APK (o Android extrai na instalação):
        // o APK cai de ~40 para ~23 MB, melhor para baixar e instalar fora da loja.
        jniLibs.useLegacyPackaging = true
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Jam: Nearby Connections (Bluetooth + Wi-Fi Direct/hotspot entre celulares).
    implementation("com.google.android.gms:play-services-nearby:19.3.0")
}

// O motor Rust liga no libc++_shared.so do NDK (a parte em C++ do time-stretch),
// que o Flutter não empacota: copia do NDK, só para as ABIs deste build (Sync
// apaga as de builds anteriores).
val copyCxxShared by tasks.registering(Sync::class) {
    val prebuilt = android.ndkDirectory.resolve("toolchains/llvm/prebuilt")
    val host = prebuilt.listFiles()?.firstOrNull { it.isDirectory }
        ?: throw GradleException("NDK sem toolchain em $prebuilt")
    for (platform in targetPlatforms) {
        val (abi, triple) = abiTriples.getValue(platform)
        from(host.resolve("sysroot/usr/lib/$triple/libc++_shared.so")) { into(abi) }
    }
    into(layout.buildDirectory.dir("cxx-shared"))
}
tasks.named("preBuild") { dependsOn(copyCxxShared) }
