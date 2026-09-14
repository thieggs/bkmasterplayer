package io.github.playermusica.player_musica

import android.content.Context
import io.flutter.app.FlutterApplication

class BkApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        // O motor em Rust abre o áudio (AAudio) pelo cpal, que precisa da JVM e
        // do Context. O Dart carrega a biblioteca por dlopen, que não passa pela
        // JVM; carregar aqui antes chama o JNI_OnLoad, e o dlopen do Dart depois
        // reaproveita a mesma biblioteca já carregada.
        System.loadLibrary("player_engine")
        initNative(applicationContext)
    }

    private external fun initNative(context: Context)
}
