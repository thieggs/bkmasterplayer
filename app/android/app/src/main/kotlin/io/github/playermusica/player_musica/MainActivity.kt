package io.github.playermusica.player_musica

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// A activity compartilha o FlutterEngine com o serviço de mídia (audio_service):
// a música continua com a tela fechada, e os botões do fone/caixa Bluetooth, da
// notificação e da tela de bloqueio chegam ao app.
class MainActivity : AudioServiceActivity() {
    private var system: MethodChannel? = null

    /** Tela a abrir vinda de uma notificação (ex.: "/jam"). */
    private var pendingRoute: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingRoute = intent?.getStringExtra("route")
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra("route")?.let { route ->
            val ch = system
            if (ch != null) ch.invokeMethod("openRoute", route) else pendingRoute = route
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        system = MethodChannel(messenger, "bkplayer/system").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    // Nome que o usuário vê no aparelho (ex.: "Galaxy M35 5G"), para o Connect e a Jam.
                    "deviceName" -> result.success(deviceName())
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "launchRoute" -> {
                        result.success(pendingRoute)
                        pendingRoute = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        JamNearby(applicationContext, messenger)
    }

    private fun deviceName(): String {
        val name = Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
        return if (name.isNullOrBlank()) Build.MODEL else name
    }
}
