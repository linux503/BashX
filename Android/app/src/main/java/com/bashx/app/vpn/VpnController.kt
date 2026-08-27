package com.bashx.app.vpn

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

class VpnController(private val context: Context) {
    enum class Status { idle, connecting, connected, disconnecting }

    private val _status = MutableStateFlow(Status.idle)
    val status = _status.asStateFlow()
    var lastError: String? = null
        private set
    var connectedSince: Long = 0L
        private set
    var uploadBytes: Long = 0L
        private set
    var downloadBytes: Long = 0L
        private set

    val isConnected get() = _status.value == Status.connected
    val isBusy get() = _status.value == Status.connecting || _status.value == Status.disconnecting
    val statusText: String
        get() = when (_status.value) {
            Status.idle -> "未连接"
            Status.connecting -> "连接中…"
            Status.connected -> "已连接"
            Status.disconnecting -> "断开中…"
        }

    fun prepareIntent(): Intent? = VpnService.prepare(context)

    fun startInternal(capture: Boolean) {
        lastError = null
        _status.value = Status.connecting
        val intent = Intent(context, BashXVpnService::class.java)
            .putExtra(BashXVpnService.EXTRA_TUNNEL_CAPTURE, capture)
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
        else context.startService(intent)
        _status.value = Status.connected
        connectedSince = System.currentTimeMillis()
    }

    fun stop() {
        _status.value = Status.disconnecting
        context.startService(Intent(context, BashXVpnService::class.java).setAction(BashXVpnService.ACTION_STOP))
        _status.value = Status.idle
        connectedSince = 0
        uploadBytes = 0
        downloadBytes = 0
    }

    fun toggle(capture: Boolean) {
        if (isConnected) {
            stop()
            lastError = null
            return
        }
            if (!MihomoBridge.isAvailable) {
                lastError = "当前安装包没有 VPN 内核，无法真正联网"
                _status.value = Status.idle
                return
            }
        startInternal(capture)
    }

    fun pollTraffic() {
        if (!isConnected) return
        if (MihomoBridge.isAvailable) {
            uploadBytes = MihomoBridge.upload()
            downloadBytes = MihomoBridge.download()
        }
    }

    suspend fun selectNode(name: String) {
        putJson("http://${com.bashx.app.AppConstants.externalController}/proxies/PROXY", """{"name":"$name"}""")
    }

    suspend fun selectGroup(group: String, name: String) {
        putJson("http://${com.bashx.app.AppConstants.externalController}/proxies/$group", """{"name":"$name"}""")
    }

    suspend fun setMode(mode: String) {
        putJson("http://${com.bashx.app.AppConstants.externalController}/configs", """{"mode":"$mode"}""")
    }

    data class GroupSnapshot(val name: String, val now: String, val all: List<String>)

    suspend fun fetchGroups(): List<GroupSnapshot> {
        val body = get("http://${com.bashx.app.AppConstants.externalController}/proxies") ?: return emptyList()
        val wanted = listOf("GOOGLE", "TELEGRAM", "AUTO", "PROXY")
        return wanted.mapNotNull { name ->
            val block = Regex("\"$name\"\\s*:\\s*\\{([^}]{0,4000})\\}").find(body)?.groupValues?.get(1) ?: return@mapNotNull null
            val now = Regex("\"now\"\\s*:\\s*\"([^\"]+)\"").find(block)?.groupValues?.get(1).orEmpty()
            val all = Regex("\"all\"\\s*:\\s*\\[(.*?)]").find(block)?.groupValues?.get(1)
                ?.split(",")
                ?.map { it.trim().trim('"') }
                ?.filter { it.isNotEmpty() }
                .orEmpty()
            GroupSnapshot(name, now, all)
        }
    }

    private val http = OkHttpClient.Builder()
        .connectTimeout(2, TimeUnit.SECONDS)
        .readTimeout(4, TimeUnit.SECONDS)
        .build()

    private fun putJson(url: String, json: String) {
        runCatching {
            http.newCall(
                Request.Builder().url(url).put(json.toRequestBody("application/json".toMediaType())).build()
            ).execute().close()
        }
    }

    private fun get(url: String): String? = runCatching {
        http.newCall(Request.Builder().url(url).build()).execute().use { it.body?.string() }
    }.getOrNull()

}
