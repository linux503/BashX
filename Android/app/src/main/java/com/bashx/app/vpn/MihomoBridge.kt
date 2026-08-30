package com.bashx.app.vpn

import android.content.Context
import android.util.Log
import java.lang.reflect.Method

/**
 * gomobile AAR (`Android/libs/MihomoCore.aar`).
 * Bind uses `-javapkg=bridge` + Go package `bridge` → class `bridge.bridge.Bridge`.
 */
object MihomoBridge {
    private const val TAG = "BashXMihomo"
    private val classNames = listOf(
        "bridge.bridge.Bridge",
        "bridge.Bridge",
        "mihomocore.Bridge",
    )

    @Volatile
    var loadError: String? = null
        private set

    private var seqClass: Class<*>? = null
    private var cls: Class<*>? = null

    val isAvailable: Boolean get() = cls != null

    fun init(context: Context) {
        if (cls != null) {
            setContext(context)
            return
        }
        runCatching { System.loadLibrary("gojni") }.onFailure {
            Log.w(TAG, "loadLibrary gojni", it)
        }
        seqClass = runCatching { Class.forName("go.Seq") }.getOrNull()
        setContext(context)
        var last: Throwable? = null
        for (name in classNames) {
            val found = runCatching {
                Class.forName(name).also { c ->
                    runCatching { c.getMethod("touch").invoke(null) }
                }
            }
            if (found.isSuccess) {
                cls = found.getOrNull()
                loadError = null
                Log.i(TAG, "loaded $name version=${version()}")
                return
            }
            last = found.exceptionOrNull()
        }
        loadError = last?.message ?: "未找到 Bridge 类"
        Log.e(TAG, "Mihomo core unavailable: $loadError", last)
    }

    private fun setContext(context: Context) {
        runCatching {
            val seq = seqClass ?: Class.forName("go.Seq").also { seqClass = it }
            seq.getMethod("setContext", Context::class.java).invoke(null, context.applicationContext)
        }.onFailure { Log.w(TAG, "Seq.setContext failed", it) }
    }

    fun setHomeDir(path: String) = invoke("setHomeDir", path)
    fun setLogFile(path: String) = invoke("setLogFile", path)
    fun setOutboundInterface(name: String) = invoke("setOutboundInterface", name)
    fun configureTUNPath(socketPair: Boolean) = invoke("configureTUNPath", socketPair)
    fun setTUNFd(fd: Int): Boolean = invokeVoid("setTUNFd", fd)
    fun start(addr: String, secret: String): Boolean =
        invokeVoid("startWithExternalController", addr, secret)
    fun stop() = invoke("stopProxy")
    fun isRunning(): Boolean = invokeBool("isRunning")
    fun upload(): Long = invokeLong("getUploadTraffic")
    fun download(): Long = invokeLong("getDownloadTraffic")
    fun version(): String = invokeString("version") ?: "—"

    private fun method(name: String, argc: Int): Method? {
        val c = cls ?: return null
        return c.methods.firstOrNull { it.name.equals(name, ignoreCase = true) && it.parameterCount == argc }
    }

    private fun convert(m: Method, args: Array<out Any?>): Array<Any?> =
        Array(args.size) { i ->
            val t = m.parameterTypes[i]
            val arg = args[i]
            when {
                t == Int::class.javaPrimitiveType && arg is Long -> arg.toInt()
                t == Int::class.java && arg is Long -> arg.toInt()
                t == Long::class.javaPrimitiveType && arg is Int -> arg.toLong()
                else -> arg
            }
        }

    private fun invoke(name: String, vararg args: Any?) {
        runCatching {
            val m = method(name, args.size) ?: return
            m.invoke(null, *convert(m, args))
        }.onFailure { Log.w(TAG, "invoke $name failed", it) }
    }

    private fun invokeVoid(name: String, vararg args: Any?): Boolean {
        val m = method(name, args.size) ?: return false
        return runCatching {
            when (val r = m.invoke(null, *convert(m, args))) {
                is Boolean -> r
                null -> true // void success
                else -> true
            }
        }.onFailure {
            Log.w(TAG, "invokeVoid $name failed", it)
        }.getOrDefault(false)
    }

    private fun invokeBool(name: String, vararg args: Any?): Boolean {
        val m = method(name, args.size) ?: return false
        return runCatching {
            when (val r = m.invoke(null, *convert(m, args))) {
                is Boolean -> r
                else -> true
            }
        }.onFailure {
            Log.w(TAG, "invokeBool $name failed", it)
        }.getOrDefault(false)
    }

    private fun invokeLong(name: String): Long {
        val m = method(name, 0) ?: return 0L
        return runCatching { (m.invoke(null) as? Number)?.toLong() ?: 0L }.getOrDefault(0L)
    }

    private fun invokeString(name: String): String? {
        val m = method(name, 0) ?: return null
        return runCatching { m.invoke(null)?.toString() }.getOrNull()
    }
}
