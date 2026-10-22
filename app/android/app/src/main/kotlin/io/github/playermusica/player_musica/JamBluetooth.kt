package io.github.playermusica.player_musica

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/**
 * Festa por Bluetooth **sem o Google Play Services** (LineageOS, Huawei…),
 * só com o que o Android tem de fábrica:
 *
 * - Achar sozinho: o dono anuncia por Bluetooth LE (serviço [SERVICE_UUID]
 *   com o PSM do canal L2CAP; o nome vai na resposta ao scan) e o convidado
 *   conecta direto nesse canal (Android 10+).
 * - Manual: com os celulares pareados nas configurações do sistema, o
 *   convidado escolhe o dono na lista de pareados e conecta por RFCOMM.
 *
 * Os dois caminhos dão um socket, e por ele passa o mesmo protocolo:
 * quadros `[tipo:1][tamanho:4][dados]`. Mensagens são JSON (o Dart cuida);
 * arquivos vão em pedaços, intercalados com as mensagens, um por vez.
 */
class JamBluetooth(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        val SERVICE_UUID: UUID = UUID.fromString("6b8f2f7e-5a4d-4e8b-9c1a-b1c0de4a3a02")

        /** Id de fabricante reservado para testes: aqui leva o nome do dono. */
        const val MANUFACTURER = 0xFFFF
        private const val TAG = "JamBluetooth"

        private const val T_MSG = 0
        private const val T_FILE_START = 1
        private const val T_FILE_DATA = 2
        private const val T_FILE_END = 3
        private const val T_ACK = 4
        private const val T_PING = 5

        /** Só acorda o escritor (nunca vai para o socket). */
        private const val T_WAKE = -1
        private const val MAX_FRAME = 16 * 1024 * 1024
        private const val CHUNK = 16 * 1024
        private const val WINDOW = 128 * 1024
        private const val ACK_EVERY = 32 * 1024
        private const val PING_EVERY = 5_000L
        private const val DEAD_AFTER = 20_000L

        /** Igual ao jamMaxUpload do Dart, com folga: acima disso a conexão cai. */
        private const val MAX_FILE = 210L * 1024 * 1024
    }

    private val channel = MethodChannel(messenger, "bkplayer/bt")
    private var events: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())
    private val adapter: BluetoothAdapter?
        get() = context.getSystemService(BluetoothManager::class.java)?.adapter

    private val conns = ConcurrentHashMap<String, Conn>()
    private var l2capServer: BluetoothServerSocket? = null
    private var rfcommServer: BluetoothServerSocket? = null
    private var advertiser: AdvertiseCallback? = null
    private var hostName = ""
    private var scanner: ScanCallback? = null

    /** Aparelhos vistos no scan: conectar pelo objeto do scan mantém o tipo de endereço do BLE. */
    private val seen = ConcurrentHashMap<String, BluetoothDevice>()

    init {
        channel.setMethodCallHandler(this)
        EventChannel(messenger, "bkplayer/bt/events").setStreamHandler(this)
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

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "state" -> {
                    val a = adapter
                    result.success(
                        mapOf(
                            "adapter" to (a != null),
                            "on" to (a?.isEnabled == true),
                            // L2CAP com BLE só existe do Android 10 em diante.
                            "ble" to (a != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q),
                        )
                    )
                }
                "startHosting" -> {
                    startHosting(call.argument<String>("name") ?: "")
                    result.success(null)
                }
                "stopHosting" -> {
                    stopHosting()
                    result.success(null)
                }
                "startScan" -> {
                    startScan()
                    result.success(null)
                }
                "stopScan" -> {
                    stopScan()
                    result.success(null)
                }
                "paired" -> result.success(paired())
                "connect" -> connect(call.argument<String>("addr")!!, call.argument<Int>("psm") ?: 0, result)
                "send" -> {
                    conns[call.argument<String>("id")!!]?.sendMessage(call.argument<ByteArray>("data")!!)
                    result.success(null)
                }
                "sendFile" -> {
                    val c = conns[call.argument<String>("id")!!]
                    if (c == null) result.error("bt", "sem conexão", null)
                    else {
                        c.sendFile(call.argument<String>("fid")!!, File(call.argument<String>("path")!!))
                        result.success(null)
                    }
                }
                // Depois do aperto de mão: mexer no link durante a conexão derrubou o canal no S8.
                "boost" -> {
                    conns[call.argument<String>("id")!!]?.let { c -> c.device?.let { c.gatt = speedUp(it) } }
                    result.success(null)
                }
                "close" -> {
                    conns[call.argument<String>("id")!!]?.close()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("bt", e.message, null)
        }
    }

    // ---- Dono ----

    @SuppressLint("MissingPermission")
    private fun startHosting(name: String) {
        val a = adapter ?: throw IllegalStateException("sem Bluetooth")
        if (!a.isEnabled) throw IllegalStateException("Bluetooth desligado")
        stopHosting()
        hostName = name
        val rf = a.listenUsingInsecureRfcommWithServiceRecord("BKmasterplayer Festa", SERVICE_UUID)
        rfcommServer = rf
        acceptLoop(rf)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val l2 = a.listenUsingInsecureL2capChannel()
            l2capServer = l2
            acceptLoop(l2)
            advertise()
        }
    }

    private fun acceptLoop(server: BluetoothServerSocket) {
        thread(name = "bt-accept", isDaemon = true) {
            while (true) {
                val s = try {
                    server.accept()
                } catch (_: Exception) {
                    break // servidor fechado
                }
                val c = Conn(UUID.randomUUID().toString(), s)
                conns[c.id] = c
                emit(mapOf("e" to "incoming", "id" to c.id))
                c.start()
                // Anúncio conectável pode parar quando alguém conecta: liga de novo.
                main.post { if (l2capServer != null) advertise() }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun advertise() {
        val adv = adapter?.bluetoothLeAdvertiser ?: return
        val psm = l2capServer?.psm ?: return
        advertiser?.let { try { adv.stopAdvertising(it) } catch (_: Exception) {} }
        val cb = object : AdvertiseCallback() {
            override fun onStartFailure(errorCode: Int) {
                Log.w(TAG, "anúncio não iniciou: $errorCode")
                emit(mapOf("e" to "advertiseFailed", "code" to errorCode))
            }
        }
        advertiser = cb
        adv.startAdvertising(
            AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(true)
                .setTimeout(0)
                .build(),
            // 3 (flags) + 20 (serviço de 128 bits + PSM) cabe nos 31 bytes.
            AdvertiseData.Builder()
                .addServiceData(ParcelUuid(SERVICE_UUID), byteArrayOf((psm shr 8).toByte(), psm.toByte()))
                .setIncludeDeviceName(false)
                .setIncludeTxPowerLevel(false)
                .build(),
            AdvertiseData.Builder().addManufacturerData(MANUFACTURER, utf8Max(hostName, 27)).build(),
            cb
        )
    }

    /** Corta em [max] bytes sem partir um caractere no meio. */
    private fun utf8Max(s: String, max: Int): ByteArray {
        var t = s
        while (t.toByteArray(Charsets.UTF_8).size > max) t = t.dropLast(1)
        return t.toByteArray(Charsets.UTF_8)
    }

    @SuppressLint("MissingPermission")
    private fun stopHosting() {
        advertiser?.let { cb ->
            try {
                adapter?.bluetoothLeAdvertiser?.stopAdvertising(cb)
            } catch (_: Exception) {
            }
        }
        advertiser = null
        try { l2capServer?.close() } catch (_: Exception) {}
        try { rfcommServer?.close() } catch (_: Exception) {}
        l2capServer = null
        rfcommServer = null
    }

    // ---- Convidado ----

    @SuppressLint("MissingPermission")
    private fun startScan() {
        val a = adapter ?: throw IllegalStateException("sem Bluetooth")
        if (!a.isEnabled) throw IllegalStateException("Bluetooth desligado")
        val s = a.bluetoothLeScanner ?: throw IllegalStateException("sem scanner BLE")
        stopScan()
        val uuid = ParcelUuid(SERVICE_UUID)
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, r: ScanResult) {
                val rec = r.scanRecord ?: return
                val data = rec.getServiceData(uuid)
                val name = rec.getManufacturerSpecificData(MANUFACTURER)?.toString(Charsets.UTF_8)
                // Sem o serviço: pode ser a resposta ao scan (só o nome) de um já visto.
                if (data == null || data.size < 2) {
                    if (name != null && seen.containsKey(r.device.address)) {
                        emit(mapOf("e" to "found", "addr" to r.device.address, "name" to name))
                    }
                    return
                }
                val psm = ((data[0].toInt() and 0xFF) shl 8) or (data[1].toInt() and 0xFF)
                seen[r.device.address] = r.device
                emit(mapOf("e" to "found", "addr" to r.device.address, "psm" to psm, "name" to name))
            }

            override fun onScanFailed(errorCode: Int) {
                Log.w(TAG, "scan falhou: $errorCode")
                emit(mapOf("e" to "scanFailed", "code" to errorCode))
            }
        }
        scanner = cb
        // Sem filtro de hardware: em alguns chips o filtro por dados de serviço
        // de 128 bits não casa. A tela está acesa enquanto procura.
        s.startScan(null, ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), cb)
    }

    @SuppressLint("MissingPermission")
    private fun stopScan() {
        val cb = scanner ?: return
        scanner = null
        try {
            adapter?.bluetoothLeScanner?.stopScan(cb)
        } catch (_: Exception) {
        }
    }

    @SuppressLint("MissingPermission")
    private fun paired(): List<Map<String, String>> =
        adapter?.bondedDevices.orEmpty()
            // Fone, caixa de som, relógio… não têm Festa: só telefones e "sem classe".
            .filter { d ->
                val major = d.bluetoothClass?.majorDeviceClass
                major == null || major == android.bluetooth.BluetoothClass.Device.Major.PHONE ||
                    major == android.bluetooth.BluetoothClass.Device.Major.COMPUTER ||
                    major == android.bluetooth.BluetoothClass.Device.Major.UNCATEGORIZED
            }
            .map { mapOf("addr" to it.address, "name" to (it.name ?: it.address)) }

    /** psm > 0: canal L2CAP de um anúncio BLE; senão RFCOMM com um pareado. */
    @SuppressLint("MissingPermission")
    private fun connect(addr: String, psm: Int, result: MethodChannel.Result) {
        val a = adapter ?: return result.error("bt", "sem Bluetooth", null)
        thread(name = "bt-connect", isDaemon = true) {
            try {
                val dev = seen[addr] ?: a.getRemoteDevice(addr)
                // Scan ligado atrapalha a conexão em vários chips.
                main.post { stopScan() }
                val s = if (psm > 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    dev.createInsecureL2capChannel(psm)
                } else {
                    dev.createInsecureRfcommSocketToServiceRecord(SERVICE_UUID)
                }
                s.connect()
                val c = Conn(UUID.randomUUID().toString(), s)
                conns[c.id] = c
                c.start()
                if (psm > 0) c.device = dev
                main.post { result.success(c.id) }
            } catch (e: Exception) {
                Log.w(TAG, "conectar em $addr (psm $psm)", e)
                main.post { result.error("bt", e.message, null) }
            }
        }
    }

    /**
     * O canal L2CAP herda o ritmo do link BLE, que o sistema deixa econômico:
     * no S8 com o M35 foram ~23 KB/s (pacotes de 27 bytes), uma música em
     * minutos. Uma conexão GATT no mesmo link deixa pedir prioridade alta
     * (intervalo menor), PHY de 2 Mbps e pacotes maiores. Se o aparelho
     * recusar, só fica como estava.
     */
    @SuppressLint("MissingPermission")
    private fun speedUp(dev: BluetoothDevice): BluetoothGatt? = try {
        dev.connectGatt(context, false, object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                if (newState != BluetoothProfile.STATE_CONNECTED) return
                g.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH)
                g.setPreferredPhy(BluetoothDevice.PHY_LE_2M_MASK, BluetoothDevice.PHY_LE_2M_MASK, BluetoothDevice.PHY_OPTION_NO_PREFERRED)
                g.requestMtu(517)
            }
        }, BluetoothDevice.TRANSPORT_LE)
    } catch (e: Exception) {
        Log.w(TAG, "prioridade do link", e)
        null
    }

    // ---- Conexão ----

    /** Arquivo saindo: só conta como entregue quando o outro lado confirma tudo. */
    private class Outgoing(val fid: String, val input: FileInputStream, val size: Long) {
        var sent = 0L
        var eof = false
        var lastPct = -1
    }

    private inner class Conn(val id: String, private val socket: BluetoothSocket) {
        private val out = DataOutputStream(BufferedOutputStream(socket.outputStream, CHUNK + 8))

        /** Quadros prontos (tipo, dados): mensagens, confirmações e sinais de vida. */
        private val frames = LinkedBlockingQueue<Pair<Int, ByteArray>>()
        private val files = ConcurrentLinkedQueue<Pair<String, File>>()

        @Volatile
        private var open = true

        /** Conexão GATT só para acelerar o link (convidado, BLE). */
        var device: BluetoothDevice? = null
        var gatt: BluetoothGatt? = null

        /** Bytes do arquivo atual que o outro lado já confirmou. */
        @Volatile
        private var acked = 0L

        @Volatile
        private var lastRx = System.currentTimeMillis()
        private var lastTx = System.currentTimeMillis()

        // Arquivo chegando (um por vez).
        private var inFid: String? = null
        private var inFile: File? = null
        private var inOut: FileOutputStream? = null
        private var inBytes = 0L
        private var inAcked = 0L

        fun start() {
            thread(name = "bt-read", isDaemon = true) { readLoop() }
            thread(name = "bt-write", isDaemon = true) { writeLoop() }
        }

        fun sendMessage(data: ByteArray) {
            frames.add(T_MSG to data)
        }

        fun sendFile(fid: String, f: File) {
            files.add(fid to f)
            frames.add(T_WAKE to ByteArray(0))
        }

        private fun frame(type: Int, data: ByteArray, len: Int = data.size) {
            out.writeByte(type)
            out.writeInt(len)
            out.write(data, 0, len)
            lastTx = System.currentTimeMillis()
        }

        private fun ack(n: Long) {
            frames.add(T_ACK to java.nio.ByteBuffer.allocate(8).putLong(n).array())
        }

        /**
         * Sem controle de fluxo, despejar um arquivo no socket travou o canal
         * L2CAP de vez (S8 com LineageOS, 22/10/2026): nada passava mais, nos
         * dois sentidos, e sem erro. Agora quem recebe confirma a cada [ACK_EVERY]
         * e quem manda nunca fica mais de [WINDOW] à frente.
         */
        private fun writeLoop() {
            var cur: Outgoing? = null
            val buf = ByteArray(CHUNK)
            try {
                while (open) {
                    val now = System.currentTimeMillis()
                    // Conexão muda (o outro lado sumiu ou o canal travou): fecha em vez de esperar para sempre.
                    if (now - lastRx > DEAD_AFTER) throw IllegalStateException("sem resposta há ${(now - lastRx) / 1000} s")
                    if (now - lastTx > PING_EVERY) {
                        frame(T_PING, ByteArray(0))
                        out.flush()
                    }
                    val c = cur
                    val canSend = c != null && !c.eof && c.sent - acked < WINDOW
                    // Mensagens primeiro: a Festa continua respondendo durante um envio.
                    val f = if (canSend || (c == null && files.isNotEmpty())) frames.poll() else frames.poll(250, TimeUnit.MILLISECONDS)
                    if (f != null) {
                        if (f.first != T_WAKE) {
                            frame(f.first, f.second)
                            out.flush()
                        }
                        continue
                    }
                    if (c == null) {
                        val (fid, file) = files.poll() ?: continue
                        cur = try {
                            Outgoing(fid, FileInputStream(file), file.length()).also {
                                acked = 0
                                frame(T_FILE_START, "$fid\n${it.size}".toByteArray(Charsets.UTF_8))
                            }
                        } catch (e: Exception) {
                            emit(mapOf("e" to "fileFailed", "id" to id, "fid" to fid))
                            null
                        }
                        continue
                    }
                    // Progresso pelo que chegou do outro lado, não pelo que saiu daqui.
                    val pct = if (c.size > 0) (minOf(acked, c.size) * 100 / c.size).toInt() else 100
                    if (pct != c.lastPct) {
                        c.lastPct = pct
                        emit(mapOf("e" to "progress", "id" to id, "fid" to c.fid, "pct" to pct))
                    }
                    if (c.eof) {
                        if (acked >= c.size) {
                            cur = null
                            emit(mapOf("e" to "sent", "id" to id, "fid" to c.fid))
                        }
                        continue
                    }
                    if (!canSend) continue
                    val n = c.input.read(buf)
                    if (n > 0) {
                        frame(T_FILE_DATA, buf, n)
                        out.flush()
                        c.sent += n
                    } else {
                        frame(T_FILE_END, ByteArray(0))
                        out.flush()
                        c.input.close()
                        c.eof = true
                    }
                }
            } catch (e: Exception) {
                if (open) Log.w(TAG, "conexão $id: ${e.message}")
            } finally {
                cur?.let {
                    try { it.input.close() } catch (_: Exception) {}
                    emit(mapOf("e" to "fileFailed", "id" to id, "fid" to it.fid))
                }
                for ((fid, _) in files) emit(mapOf("e" to "fileFailed", "id" to id, "fid" to fid))
                files.clear()
                close()
            }
        }

        private fun readLoop() {
            try {
                val inp = DataInputStream(BufferedInputStream(socket.inputStream, CHUNK + 8))
                while (open) {
                    val type = inp.readUnsignedByte()
                    val len = inp.readInt()
                    if (len < 0 || len > MAX_FRAME) throw IllegalStateException("quadro de $len bytes")
                    val data = ByteArray(len)
                    inp.readFully(data)
                    lastRx = System.currentTimeMillis()
                    when (type) {
                        T_MSG -> emit(mapOf("e" to "msg", "id" to id, "data" to data))
                        T_ACK -> if (len == 8) acked = java.nio.ByteBuffer.wrap(data).long
                        T_FILE_START -> {
                            dropIncoming()
                            val dir = File(context.cacheDir, "jam").apply { mkdirs() }
                            val f = File.createTempFile("jambt", null, dir) // prefixo: 3 letras no mínimo
                            inFid = data.toString(Charsets.UTF_8).substringBefore('\n')
                            inFile = f
                            inOut = FileOutputStream(f)
                            inBytes = 0
                            inAcked = 0
                        }
                        T_FILE_DATA -> {
                            val o = inOut ?: continue
                            inBytes += len
                            if (inBytes > MAX_FILE) throw IllegalStateException("arquivo grande demais")
                            o.write(data)
                            if (inBytes - inAcked >= ACK_EVERY) {
                                inAcked = inBytes
                                ack(inBytes)
                            }
                        }
                        T_FILE_END -> {
                            val fid = inFid
                            val f = inFile
                            inOut?.close()
                            inOut = null
                            inFid = null
                            inFile = null
                            ack(inBytes)
                            if (fid != null && f != null) emit(mapOf("e" to "file", "id" to id, "fid" to fid, "path" to f.absolutePath))
                        }
                        // T_PING: só atualiza lastRx.
                    }
                }
            } catch (e: Exception) {
                if (open) Log.i(TAG, "conexão $id caiu: ${e.message}")
            } finally {
                dropIncoming()
                close()
            }
        }

        private fun dropIncoming() {
            try { inOut?.close() } catch (_: Exception) {}
            inFile?.delete()
            inOut = null
            inFile = null
            inFid = null
        }

        fun close() {
            if (!open) return
            open = false
            frames.add(T_WAKE to ByteArray(0))
            try { socket.close() } catch (_: Exception) {}
            try { gatt?.close() } catch (_: Exception) {}
            conns.remove(id)
            emit(mapOf("e" to "closed", "id" to id))
        }
    }
}
