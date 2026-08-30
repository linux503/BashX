package com.bashx.app.ui.fold

import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Galaxy Z Fold 6: cover ~360×880 dp, inner ~796×927 dp (near-square). */
data class FoldMetrics(
    val isCover: Boolean,
    val pagePad: Dp,
    val cardPad: Dp,
    val cardRadius: Dp,
    val brandSize: Dp,
    val brandCorner: Dp,
    val connectSize: Dp,
    val titleSize: TextUnit,
    val subtitleSize: TextUnit,
    val iconSize: Dp,
    val buttonHeight: Dp,
    val nodeColumns: Int,
    val subColumns: Int,
    val settingsColumns: Int,
    val locationIcon: Dp,
) {
    companion object {
        /** Cover display — narrow tall phone. */
        val cover = FoldMetrics(
            isCover = true,
            pagePad = 16.dp,
            cardPad = 14.dp,
            cardRadius = 18.dp,
            brandSize = 48.dp,
            brandCorner = 12.dp,
            connectSize = 168.dp,
            titleSize = 26.sp,
            subtitleSize = 13.sp,
            iconSize = 22.dp,
            buttonHeight = 48.dp,
            nodeColumns = 1,
            subColumns = 1,
            settingsColumns = 1,
            locationIcon = 40.dp,
        )

        /** Inner display — almost square tablet. */
        val inner = FoldMetrics(
            isCover = false,
            pagePad = 20.dp,
            cardPad = 18.dp,
            cardRadius = 22.dp,
            brandSize = 64.dp,
            brandCorner = 16.dp,
            connectSize = 196.dp,
            titleSize = 30.sp,
            subtitleSize = 14.sp,
            iconSize = 24.dp,
            buttonHeight = 52.dp,
            nodeColumns = 2,
            subColumns = 2,
            settingsColumns = 2,
            locationIcon = 48.dp,
        )
    }
}

val LocalFold = compositionLocalOf { FoldMetrics.cover }
