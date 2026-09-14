package io.github.playermusica.player_musica

import android.os.Build
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// A activity compartilha o FlutterEngine com o serviço de mídia (audio_service):
// a música continua com a tela fechada, e os botões do fone/caixa Bluetooth, da
// notificação e da tela de bloqueio chegam ao app.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bkplayer/system").setMethodCallHandler { call, result ->
            when (call.method) {
                // Nome que o usuário vê no aparelho (ex.: "Galaxy M35 5G"), para o Connect.
                "deviceName" -> result.success(deviceName())
                else -> result.notImplemented()
            }
        }
    }

    private fun deviceName(): String {
        val name = Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
        return if (name.isNullOrBlank()) Build.MODEL else name
    }
}
