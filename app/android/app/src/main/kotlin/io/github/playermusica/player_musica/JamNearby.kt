package io.github.playermusica.player_musica

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/**
 * Jam por Bluetooth/Wi-Fi Direct (Nearby Connections) e o "beacon":
 *
 * - Nearby: o dono anuncia a Jam, o convidado acha e pede para entrar; a
 *   biblioteca do Google negocia por Bluetooth e passa os arquivos pelo meio
 *   mais rápido (Wi-Fi Direct/hotspot). O dono aceita ou recusa cada pedido.
 * - Beacon: anúncio Bluetooth LE com o UUID da Jam enquanto ela está aberta.
 *   O celular do convidado deixa um scan com o sistema (continua com o app
 *   fechado) e mostra uma notificação quando passa perto de uma Jam.
 * - Pedido de entrada como notificação (Aceitar / Recusar / Sempre), para o
 *   dono com o app em segundo plano.
 */
class JamNearby(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val SERVICE_ID = "io.github.playermusica.player_musica.jam"
        val BEACON_UUID: UUID = UUID.fromString("6b8f2f7e-5a4d-4e8b-9c1a-b1c0de4a3a01")
        const val CHANNEL_NEARBY = "jam_nearby"
        const val CHANNEL_REQUESTS = "jam_requests"
        const val PREFS = "bkplayer_jam"
        private const val TAG = "JamNearby"

        /** Canal ativo (o receiver das notificações repassa a decisão por ele). */
        @Volatile
        var active: JamNearby? = null
    }

    private val client = Nearby.getConnectionsClient(context)
    val channel = MethodChannel(messenger, "bkplayer/nearby")
    private var events: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())
    private val incomingFiles = HashMap<Long, Payload>()
    private val lastProgress = HashMap<Long, Int>()
    private var advertiser: AdvertiseCallback? = null

    init {
        channel.setMethodCallHandler(this)
        EventChannel(messenger, "bkplayer/nearby/events").setStreamHandler(this)
        active = this
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    private fun emit(m: Map<String, Any?>) {
        main.post { events?.success(m) }
    }

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            when (payload.type) {
                Payload.Type.BYTES -> emit(mapOf("e" to "bytes", "id" to endpointId, "data" to payload.asBytes()))
                Payload.Type.FILE -> incomingFiles[payload.id] = payload
                else -> {}
            }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {
            val id = update.payloadId
            when (update.status) {
                PayloadTransferUpdate.Status.IN_PROGRESS -> {
                    val total = update.totalBytes
                    if (total > 0) {
                        val pct = (update.bytesTransferred * 100 / total).toInt()
                        if (pct != lastProgress[id]) {
                            lastProgress[id] = pct
                            emit(mapOf("e" to "progress", "id" to endpointId, "payloadId" to id, "pct" to pct))
                        }
                    }
                }
                PayloadTransferUpdate.Status.SUCCESS -> {
                    lastProgress.remove(id)
                    val p = incomingFiles.remove(id)
                    if (p == null) {
                        emit(mapOf("e" to "sent", "id" to endpointId, "payloadId" to id))
                    } else {
                        val path = saveIncoming(p)
                        if (path != null) {
                            emit(mapOf("e" to "file", "id" to endpointId, "payloadId" to id, "path" to path))
                        } else {
                            emit(mapOf("e" to "fileFailed", "id" to endpointId, "payloadId" to id))
                        }
                    }
                }
                else -> {
                    lastProgress.remove(id)
                    incomingFiles.remove(id)
                    emit(mapOf("e" to "fileFailed", "id" to endpointId, "payloadId" to id))
                }
            }
        }
    }

    /** Copia o arquivo recebido para o cache do app (cache/jam) e devolve o caminho. */
    @Suppress("DEPRECATION")
    private fun saveIncoming(p: Payload): String? {
        val dir = File(context.cacheDir, "jam").apply { mkdirs() }
        val out = File(dir, "nb${p.id.toString().replace('-', 'n')}")
        return try {
            val f = p.asFile() ?: return null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val uri = f.asUri() ?: return null
                context.contentResolver.openInputStream(uri)?.use { input ->
                    out.outputStream().use { input.copyTo(it) }
                }
                context.contentResolver.delete(uri, null, null)
            } else {
                val src = f.asJavaFile() ?: return null
                if (!src.renameTo(out)) {
                    src.copyTo(out, overwrite = true)
                    src.delete()
                }
            }
            out.absolutePath
        } catch (e: Exception) {
            Log.w(TAG, "arquivo recebido", e)
            null
        }
    }

    private val lifecycle = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            emit(
                mapOf(
                    "e" to "initiated",
                    "id" to endpointId,
                    "info" to String(info.endpointInfo, Charsets.UTF_8),
                    "incoming" to info.isIncomingConnection,
                )
            )
        }

        override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
            emit(mapOf("e" to if (result.status.isSuccess) "connected" else "rejected", "id" to endpointId))
        }

        override fun onDisconnected(endpointId: String) {
            emit(mapOf("e" to "disconnected", "id" to endpointId))
        }
    }

    private val discovery = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            emit(mapOf("e" to "found", "id" to endpointId, "info" to String(info.endpointInfo, Charsets.UTF_8)))
        }

        override fun onEndpointLost(endpointId: String) {
            emit(mapOf("e" to "lost", "id" to endpointId))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val strategy = Strategy.P2P_STAR
        fun ok() = result.success(null)
        fun fail(e: Exception) = result.error("nearby", e.message, null)
        try {
            when (call.method) {
                "available" -> result.success(
                    GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS
                )
                "startAdvertising" -> client.startAdvertising(
                    call.argument<ByteArray>("info")!!, SERVICE_ID, lifecycle,
                    AdvertisingOptions.Builder().setStrategy(strategy).build()
                ).addOnSuccessListener { ok() }.addOnFailureListener { fail(it) }
                "stopAdvertising" -> { client.stopAdvertising(); ok() }
                "startDiscovery" -> client.startDiscovery(
                    SERVICE_ID, discovery, DiscoveryOptions.Builder().setStrategy(strategy).build()
                ).addOnSuccessListener { ok() }.addOnFailureListener { fail(it) }
                "stopDiscovery" -> { client.stopDiscovery(); ok() }
                "requestConnection" -> client.requestConnection(
                    call.argument<ByteArray>("info")!!, call.argument<String>("id")!!, lifecycle
                ).addOnSuccessListener { ok() }.addOnFailureListener { fail(it) }
                "accept" -> client.acceptConnection(call.argument<String>("id")!!, payloadCallback)
                    .addOnSuccessListener { ok() }.addOnFailureListener { fail(it) }
                "reject" -> client.rejectConnection(call.argument<String>("id")!!)
                    .addOnSuccessListener { ok() }.addOnFailureListener { fail(it) }
                "disconnect" -> { client.disconnectFromEndpoint(call.argument<String>("id")!!); ok() }
                "sendBytes" -> client.sendPayload(call.argument<String>("id")!!, Payload.fromBytes(call.argument<ByteArray>("data")!!))
                    .addOnSuccessListener { ok() }.addOnFailureListener { fail(it) }
                "sendFile" -> {
                    val pfd = ParcelFileDescriptor.open(File(call.argument<String>("path")!!), ParcelFileDescriptor.MODE_READ_ONLY)
                    val payload = Payload.fromFile(pfd)
                    client.sendPayload(call.argument<String>("id")!!, payload)
                        .addOnSuccessListener { result.success(payload.id) }.addOnFailureListener { fail(it) }
                }
                "stopAll" -> {
                    client.stopAdvertising()
                    client.stopDiscovery()
                    client.stopAllEndpoints()
                    stopBeacon()
                    ok()
                }
                "startBeacon" -> { startBeacon(); ok() }
                "stopBeacon" -> { stopBeacon(); ok() }
                "setBeaconScan" -> { setBeaconScan(call.argument<Boolean>("on") == true); ok() }
                "setHosting" -> {
                    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                        .putBoolean("hosting", call.argument<Boolean>("on") == true).apply()
                    ok()
                }
                "showJoinRequest" -> {
                    showJoinRequest(call.argument<String>("key")!!, call.argument<String>("name")!!, call.argument<String>("title")!!,
                        call.argument<String>("accept")!!, call.argument<String>("reject")!!, call.argument<String>("always")!!)
                    ok()
                }
                "cancelJoinRequest" -> {
                    context.getSystemService(NotificationManager::class.java)
                        .cancel(call.argument<String>("key")!!.hashCode())
                    ok()
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            fail(e)
        }
    }

    // ---- Beacon (Bluetooth LE) ----

    @SuppressLint("MissingPermission")
    private fun startBeacon() {
        val adv = context.getSystemService(BluetoothManager::class.java)?.adapter?.bluetoothLeAdvertiser ?: return
        stopBeacon()
        val cb = object : AdvertiseCallback() {
            override fun onStartFailure(errorCode: Int) {
                Log.w(TAG, "beacon não iniciou: $errorCode")
            }
        }
        advertiser = cb
        adv.startAdvertising(
            AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                .setConnectable(false)
                .build(),
            AdvertiseData.Builder().addServiceUuid(ParcelUuid(BEACON_UUID)).setIncludeDeviceName(false).build(),
            cb
        )
    }

    @SuppressLint("MissingPermission")
    private fun stopBeacon() {
        val cb = advertiser ?: return
        advertiser = null
        try {
            context.getSystemService(BluetoothManager::class.java)?.adapter?.bluetoothLeAdvertiser?.stopAdvertising(cb)
        } catch (_: Exception) {
        }
    }

    private fun beaconIntent(): PendingIntent {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
        return PendingIntent.getBroadcast(context, 7101, Intent(context, JamBeaconReceiver::class.java), flags)
    }

    /** Scan com o sistema: continua com o app fechado (até reiniciar o aparelho). */
    @SuppressLint("MissingPermission")
    private fun setBeaconScan(on: Boolean) {
        val scanner = context.getSystemService(BluetoothManager::class.java)?.adapter?.bluetoothLeScanner ?: return
        try {
            scanner.stopScan(beaconIntent())
        } catch (_: Exception) {
        }
        if (!on) return
        scanner.startScan(
            listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(BEACON_UUID)).build()),
            ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_POWER).build(),
            beaconIntent()
        )
    }

    // ---- Pedido de entrada como notificação ----

    private fun showJoinRequest(key: String, name: String, title: String, accept: String, reject: String, always: String) {
        val nm = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm.getNotificationChannel(CHANNEL_REQUESTS) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL_REQUESTS, if (java.util.Locale.getDefault().language == "pt") "Festa" else "Party", NotificationManager.IMPORTANCE_HIGH))
        }
        fun action(what: String, code: Int): PendingIntent {
            val i = Intent(context, JamActionReceiver::class.java).putExtra("key", key).putExtra("what", what)
            return PendingIntent.getBroadcast(context, key.hashCode() * 4 + code, i,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val open = PendingIntent.getActivity(context, key.hashCode(),
            Intent(context, MainActivity::class.java).putExtra("route", "/jam").addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(context, CHANNEL_REQUESTS)
            .setSmallIcon(R.drawable.ic_stat_bk)
            .setContentTitle(title)
            .setContentText(name)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setAutoCancel(true)
            .setContentIntent(open)
            .addAction(0, reject, action("reject", 0))
            .addAction(0, accept, action("accept", 1))
            .addAction(0, always, action("always", 2))
            .build()
        nm.notify(key.hashCode(), n)
    }
}

/** Botões da notificação do pedido de entrada → Dart. */
class JamActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val key = intent.getStringExtra("key") ?: return
        val what = intent.getStringExtra("what") ?: return
        context.getSystemService(NotificationManager::class.java).cancel(key.hashCode())
        JamNearby.active?.channel?.invokeMethod("jamDecision", mapOf("key" to key, "what" to what))
    }
}

/** Resultado do scan em segundo plano: tem uma Jam por perto. */
class JamBeaconReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences(JamNearby.PREFS, Context.MODE_PRIVATE)
        if (prefs.getBoolean("hosting", false)) return
        val now = System.currentTimeMillis()
        // No máximo um aviso a cada 30 minutos.
        if (now - prefs.getLong("lastNotified", 0) < 30 * 60 * 1000) return
        prefs.edit().putLong("lastNotified", now).apply()
        val nm = context.getSystemService(NotificationManager::class.java)
        val pt = java.util.Locale.getDefault().language == "pt"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm.getNotificationChannel(JamNearby.CHANNEL_NEARBY) == null) {
            nm.createNotificationChannel(
                NotificationChannel(JamNearby.CHANNEL_NEARBY, if (pt) "Festas por perto" else "Parties nearby", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val open = PendingIntent.getActivity(context, 7102,
            Intent(context, MainActivity::class.java).putExtra("route", "/jam").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(context, JamNearby.CHANNEL_NEARBY)
            .setSmallIcon(R.drawable.ic_stat_bk)
            .setContentTitle(if (pt) "Tem uma Festa do BKT Player perto de você" else "There's a BKT Player Party near you")
            .setContentText(if (pt) "Toque para pedir para entrar e mandar suas músicas" else "Tap to ask to join and add your songs")
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        nm.notify(7102, n)
    }
}
