package io.github.playermusica.player_musica

import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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

    /** Vigia do volume de mídia, ligado só quando o app usa alguma regra dele. */
    private var volumeWatch: ContentObserver? = null

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
                    // Volume de mídia do aparelho (os botões do lado), que o
                    // Flutter não enxerga sozinho.
                    "mediaVolume" -> result.success(mediaVolume())
                    "watchVolume" -> {
                        if (call.arguments == true) startVolumeWatch() else stopVolumeWatch()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        JamNearby(applicationContext, messenger)
    }

    private fun audioManager() = getSystemService(Context.AUDIO_SERVICE) as AudioManager

    /** Volume de mídia agora, de 0 a 1. */
    private fun mediaVolume(): Double {
        val am = audioManager()
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return 0.0
        return am.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max
    }

    // O Android não tem aviso público de "o volume mudou": o jeito que
    // funciona em todas as versões é observar as configurações do sistema e
    // reler o volume. Por isso o filtro de repetido — cada mexida dispara
    // várias vezes.
    private fun startVolumeWatch() {
        if (volumeWatch != null) return
        var last = -1.0
        val obs = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                val v = mediaVolume()
                if (v == last) return
                last = v
                system?.invokeMethod("mediaVolume", v)
            }
        }
        contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, obs)
        volumeWatch = obs
    }

    private fun stopVolumeWatch() {
        volumeWatch?.let { contentResolver.unregisterContentObserver(it) }
        volumeWatch = null
    }

    override fun onDestroy() {
        stopVolumeWatch()
        super.onDestroy()
    }

    private fun deviceName(): String {
        val name = Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
        return if (name.isNullOrBlank()) Build.MODEL else name
    }
}
