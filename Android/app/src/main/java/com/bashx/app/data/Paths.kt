package com.bashx.app.data

import android.content.Context
import java.io.File

object Paths {
    private lateinit var root: File

    fun init(context: Context) {
        root = File(context.filesDir, "BashX").apply { mkdirs() }
        File(root, "subs").mkdirs()
        File(root, "mihomo").mkdirs()
    }

    val supportDir: File get() = root
    val settingsFile: File get() = File(root, "settings.json")
    val configFile: File get() = File(root, "config.yaml")
    val mihomoHome: File get() = File(root, "mihomo").apply { mkdirs() }
    val mihomoConfig: File get() = File(mihomoHome, "config.yaml")
    val tunnelLog: File get() = File(root, "tunnel.log")
    val subsDir: File get() = File(root, "subs").apply { mkdirs() }

    fun subscriptionCache(id: String): File = File(subsDir, "$id.bin")
}
