package com.bashx.app.data

object ByteFormat {
    fun size(bytes: Long): String {
        val v = maxOf(0, bytes).toDouble()
        return when {
            v < 1024 -> "%.0f B".format(v)
            v < 1024 * 1024 -> "%.1f KB".format(v / 1024)
            v < 1024 * 1024 * 1024 -> "%.2f MB".format(v / (1024 * 1024))
            else -> "%.2f GB".format(v / (1024 * 1024 * 1024))
        }
    }

    fun rate(bytesPerSec: Long): String {
        val m = maxOf(0, bytesPerSec).toDouble() / (1024.0 * 1024.0)
        return if (m >= 100) "%.0f M/s".format(m.coerceAtMost(9999.0))
        else "%.1f M/s".format(m.coerceAtMost(99.9))
    }
}
