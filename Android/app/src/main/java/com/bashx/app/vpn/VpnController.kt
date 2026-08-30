package com.bashx.app.vpn

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
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
    private var connectingSince: Long = 0L

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
        // Android has no system HTTP proxy path — require full TUN capture.
        if (!capture) {
            lastError = "Android 仅支持 TUN 全量接管（无系统代理模式）"
            _status.value = Status.idle
            return
        }
        if (!MihomoBridge.isAvailable) {
            lastError = "当前安装包没有 VPN 内核，无法真正联网"
            _status.value = Status.idle
            return
        }
        _status.value = Status.connecting
        connectingSince = System.currentTimeMillis()
        connectedSince = 0L
        val intent = Intent(context, BashXVpnService::class.java)
            .putExtra(BashXVpnService.EXTRA_TUNNEL_CAPTURE, true)
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
        else context.startService(intent)
        // Stay in connecting until pollTraffic sees MihomoBridge.isRunning().
    }

    fun stop() {
        _status.value = Status.disconnecting
        context.startService(Intent(context, BashXVpnService::class.java).setAction(BashXVpnService.ACTION_STOP))
        _status.value = Status.idle
        connectedSince = 0
        connectingSince = 0
        uploadBytes = 0
        downloadBytes = 0
    }

    fun toggle(capture: Boolean) {
        if (isConnected || _status.value == Status.connecting) {
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
        when (_status.value) {
            Status.connecting -> {
                if (MihomoBridge.isRunning()) {
                    _status.value = Status.connected
                    connectedSince = System.currentTimeMillis()
                    lastError = null
                } else if (System.currentTimeMillis() - connectingSince > 12_000) {
                    lastError = "VPN 启动超时（内核未就绪）"
                    _status.value = Status.idle
                    connectingSince = 0
                }
                return
            }
            Status.connected -> {
                if (!MihomoBridge.isRunning()) {
                    lastError = "VPN 已断开"
                    _status.value = Status.idle
                    connectedSince = 0
                    uploadBytes = 0
                    downloadBytes = 0
                    return
                }
            }
            else -> return
        }
        if (MihomoBridge.isAvailable) {
            uploadBytes = MihomoBridge.upload()
            downloadBytes = MihomoBridge.download()
        }
    }

    suspend fun selectNode(name: String) = withContext(Dispatchers.IO) {
        putJson(
            "http://${com.bashx.app.AppConstants.externalController}/proxies/PROXY",
            JSONObject().put("name", name).toString(),
        )
    }

    suspend fun selectGroup(group: String, name: String) = withContext(Dispatchers.IO) {
        putJson(
            "http://${com.bashx.app.AppConstants.externalController}/proxies/$group",
            JSONObject().put("name", name).toString(),
        )
    }

    suspend fun setMode(mode: String) = withContext(Dispatchers.IO) {
        putJson(
            "http://${com.bashx.app.AppConstants.externalController}/configs",
            JSONObject().put("mode", mode).toString(),
        )
    }

    data class GroupSnapshot(val name: String, val now: String, val all: List<String>)

    suspend fun fetchGroups(): List<GroupSnapshot> = withContext(Dispatchers.IO) {
        val body = get("http://${com.bashx.app.AppConstants.externalController}/proxies") ?: return@withContext emptyList()
        val root = runCatching { JSONObject(body) }.getOrNull() ?: return@withContext emptyList()
        val proxies = root.optJSONObject("proxies") ?: return@withContext emptyList()
        val wanted = listOf("GOOGLE", "TELEGRAM", "AUTO", "PROXY", "AI", "JP", "HK", "US")
        wanted.mapNotNull { name ->
            val obj = proxies.optJSONObject(name) ?: return@mapNotNull null
            val now = obj.optString("now")
            val all = buildList {
                val arr = obj.optJSONArray("all") ?: return@buildList
                for (i in 0 until arr.length()) {
                    val item = arr.optString(i)
                    if (item.isNotEmpty()) add(item)
                }
            }
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
