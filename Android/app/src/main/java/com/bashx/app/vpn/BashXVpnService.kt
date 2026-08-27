package com.bashx.app.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import com.bashx.app.AppConstants
import com.bashx.app.MainActivity
import com.bashx.app.R
import com.bashx.app.data.Paths
import java.io.File

class BashXVpnService : VpnService() {
    private var tun: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopVpn()
                return START_NOT_STICKY
            }
            else -> startVpn(intent?.getBooleanExtra(EXTRA_TUNNEL_CAPTURE, true) != false)
        }
        return START_STICKY
    }

    private fun startVpn(tunnelCapture: Boolean) {
        startForeground(AppConstants.notificationId, notification())
        Paths.tunnelLog.writeText("startVpn tunnelCapture=$tunnelCapture core=${MihomoBridge.isAvailable}\n")
        if (!MihomoBridge.isAvailable) {
            appendLog("VPN 内核未打进安装包")
            stopVpn()
            return
        }
        val config = Paths.mihomoConfig
        if (!config.exists()) {
            appendLog("config missing: ${config.absolutePath}")
            stopVpn()
            return
        }

        runCatching { tun?.close() }
        tun = null

        val builder = Builder()
            .setSession("BashX")
            .setMtu(AppConstants.defaultMTU)
            .addAddress(AppConstants.tunAddress, AppConstants.tunPrefix)
            .addDnsServer(AppConstants.tunDNS)
            .setBlocking(false)
        if (tunnelCapture) {
            builder.addRoute("0.0.0.0", 0)
        }
        if (Build.VERSION.SDK_INT >= 29) {
            builder.setMetered(false)
        }
        val pfd = builder.establish()
        if (pfd == null) {
            appendLog("VpnService.establish() failed")
            stopVpn()
            return
        }
        tun = pfd
        val bindIF = underlyingIface()
        MihomoBridge.setLogFile(Paths.tunnelLog.absolutePath)
        MihomoBridge.setHomeDir(Paths.mihomoHome.absolutePath)
        MihomoBridge.setOutboundInterface(bindIF)
        MihomoBridge.configureTUNPath(false)
        if (tunnelCapture) {
            val ok = MihomoBridge.setTUNFd(pfd.fd)
            appendLog("SetTUNFd fd=${pfd.fd} ok=$ok bindIF=$bindIF")
            if (!ok) {
                stopVpn()
                return
            }
        }
        val started = MihomoBridge.start(AppConstants.externalController, "")
        appendLog("start controller=${AppConstants.externalController} ok=$started running=${MihomoBridge.isRunning()}")
        if (!started) stopVpn()
    }

    private fun stopVpn() {
        runCatching { MihomoBridge.stop() }
        runCatching { tun?.close() }
        tun = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        appendLog("vpn stopped")
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopVpn()
        super.onRevoke()
    }

    private fun underlyingIface(): String {
        val cm = getSystemService(ConnectivityManager::class.java)
        val net = cm.activeNetwork ?: return ""
        val lp = cm.getLinkProperties(net)
        return lp?.interfaceName.orEmpty()
    }

    private fun notification(): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    AppConstants.notificationChannelId,
                    "BashX VPN",
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }
        val launch = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, AppConstants.notificationChannelId)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.vpn_notification))
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentIntent(launch)
            .setOngoing(true)
            .build()
    }

    private fun appendLog(line: String) {
        Log.i(TAG, line)
        runCatching { Paths.tunnelLog.appendText(line + "\n") }
    }

    companion object {
        const val ACTION_STOP = "com.bashx.app.STOP_VPN"
        const val EXTRA_TUNNEL_CAPTURE = "tunnelCapture"
        private const val TAG = "BashXVpn"
    }
}
