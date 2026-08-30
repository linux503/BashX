package com.bashx.app.ui.theme

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/** Matches BashXiOS `IOSTheme` (sky azure) + default markX yellow for the brand glyph. */
object BashXTheme {
    val accent = Color(0xFF38A3F5)
    val accentDeep = Color(0xFF1A6BC7)
    val accentBright = Color(0xFF85D1FF)
    val accentSoft = Color(0x2938A3F5)
    val ink = Color(0xFF142438)
    val mist = Color(0xFFEBF5FF)
    val good = Color(0xFF2ED670)
    val warn = Color(0xFFFFBD47)
    val bad = Color(0xFFFF523D)
    val grouped = Color(0xFFF2F2F7)
    val card = Color(0xFFFFFFFF)
    val stroke = Color(0x0F000000)

    val accentGradient = Brush.linearGradient(
        colors = listOf(
            Color(0xFF8CD6FF),
            Color(0xFF38A3F5),
            Color(0xFF1466C7),
        )
    )

    val markYellow = Color(0xFFFFD61F)
    val markYellowDeep = Color(0xFFEBAD0A)
    val markYellowBright = Color(0xFFFFF061)
    val markInk = Color(0xFF1F1A0A)
    val markInkSoft = Color(0xFF4D380F)

    fun delayColor(ms: Int?): Color = when {
        ms == null -> Color(0xFF8A8A8E)
        ms < 0 -> bad
        ms < 150 -> good
        ms < 400 -> warn
        else -> bad
    }
}
