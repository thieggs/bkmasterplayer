package io.github.playermusica.player_musica

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Capas para o Android Auto, que só aceita `content://` nas listas.
 *
 * `content://<app>.art/c/<chave>`: o app (Dart) grava a fonte da capa em
 * `cache/aa_art/<chave>.src` (URL do servidor, com o token, ou caminho de um
 * arquivo do aparelho); aqui ela é baixada uma vez e servida. Só serve o que o
 * app registrou: a URI leva apenas a chave, nunca a URL nem o token.
 */
class BkArtProvider : ContentProvider() {
    override fun onCreate() = true

    override fun getType(uri: Uri) = "image/jpeg"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val key = uri.lastPathSegment?.takeIf { KEY.matches(it) } ?: throw FileNotFoundException(uri.toString())
        val dir = File(context!!.cacheDir, "aa_art")
        val img = File(dir, "$key.img")
        if (!img.exists()) {
            val src = File(dir, "$key.src").takeIf { it.exists() }?.readText()?.trim()
                ?: throw FileNotFoundException(key)
            if (src.startsWith("/")) {
                return ParcelFileDescriptor.open(File(src), ParcelFileDescriptor.MODE_READ_ONLY)
            }
            // Numa thread à parte: o Binder traz a regra do StrictMode de quem
            // chamou (se veio da thread principal dele, rede aqui seria proibida).
            try {
                pool.submit { download(src, img) }.get(20, TimeUnit.SECONDS)
            } catch (e: Exception) {
                throw FileNotFoundException("capa: ${e.cause ?: e}")
            }
        }
        return ParcelFileDescriptor.open(img, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    private fun download(url: String, out: File) {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 8000
        conn.readTimeout = 15000
        try {
            if (conn.responseCode != 200) throw FileNotFoundException("HTTP ${conn.responseCode}")
            val tmp = File(out.parentFile, "${out.name}.${Thread.currentThread().id}.part")
            conn.inputStream.use { input -> tmp.outputStream().use { input.copyTo(it) } }
            if (tmp.length() < 100 || !tmp.renameTo(out)) {
                tmp.delete()
                throw FileNotFoundException("capa vazia")
            }
        } finally {
            conn.disconnect()
        }
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0

    private companion object {
        val KEY = Regex("^[0-9a-f]{16,40}$")
        val pool: ExecutorService = Executors.newFixedThreadPool(3)
    }
}
