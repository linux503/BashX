package com.bashx.app.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bashx.app.R
import com.bashx.app.ui.fold.LocalFold
import com.bashx.app.ui.theme.BashXTheme
import com.bashx.app.vpn.VpnController

@Composable
fun ConnectButton(
    status: VpnController.Status,
    enabled: Boolean,
    size: Dp = LocalFold.current.connectSize,
    onClick: () -> Unit,
) {
    val connected = status == VpnController.Status.connected
    val busy = status == VpnController.Status.connecting || status == VpnController.Status.disconnecting
    val pulse = rememberInfiniteTransition(label = "pulse")
    val scale by pulse.animateFloat(
        1f, if (connected) 1.08f else 1f,
        infiniteRepeatable(tween(1800), RepeatMode.Reverse),
        label = "s",
    )
    val spin by pulse.animateFloat(
        0f, 360f,
        infiniteRepeatable(tween(1400, easing = LinearEasing), RepeatMode.Restart),
        label = "r",
    )
    val fill = if (connected) BashXTheme.good else BashXTheme.accent
    Box(
        modifier = Modifier
            .size(size)
            .scale(if (enabled) 1f else 0.92f)
            .clickable(enabled = enabled && !busy, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(size)) {
            val canvas = this.size
            val min = canvas.minDimension
            drawCircle(fill.copy(alpha = if (connected) 0.22f else 0.12f), radius = min / 2.2f * scale)
            drawCircle(
                brush = Brush.linearGradient(listOf(fill, fill.copy(alpha = 0.45f))),
                radius = min * 0.43f,
                style = Stroke((min * 0.017f).coerceAtLeast(2.5f)),
            )
            if (busy) {
                val arc = min * 0.47f
                drawArc(
                    color = BashXTheme.warn.copy(alpha = 0.7f),
                    startAngle = spin,
                    sweepAngle = 260f,
                    useCenter = false,
                    topLeft = Offset(canvas.width / 2 - arc, canvas.height / 2 - arc),
                    size = Size(arc * 2, arc * 2),
                    style = Stroke(min * 0.012f, cap = StrokeCap.Round),
                )
            }
            drawCircle(
                brush = Brush.linearGradient(
                    listOf(fill, fill.copy(alpha = 0.75f)),
                    start = Offset.Zero,
                    end = Offset(canvas.width, canvas.height),
                ),
                radius = min * 0.36f,
            )
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            if (busy) {
                CircularProgressIndicator(
                    color = Color.White,
                    modifier = Modifier.size(size * 0.14f),
                    strokeWidth = 2.dp,
                )
            } else {
                Icon(
                    if (connected) Icons.Default.Check else Icons.Default.PowerSettingsNew,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(size * 0.17f),
                )
            }
            Spacer(Modifier.height(6.dp))
            Text(
                when {
                    busy -> "连接中"
                    connected -> "已连接"
                    else -> "连接"
                },
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = if (LocalFold.current.isCover) 12.sp else 14.sp,
            )
        }
    }
}

@Composable
fun StatusPill(text: String, status: VpnController.Status) {
    val color = when (status) {
        VpnController.Status.connected -> BashXTheme.good
        VpnController.Status.connecting, VpnController.Status.disconnecting -> BashXTheme.warn
        else -> Color(0xFF8A8A8E)
    }
    val cover = LocalFold.current.isCover
    Row(
        Modifier
            .clip(RoundedCornerShape(50))
            .background(color.copy(alpha = 0.10f))
            .padding(horizontal = if (cover) 12.dp else 16.dp, vertical = if (cover) 6.dp else 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(if (cover) 7.dp else 8.dp)
                .clip(CircleShape)
                .background(color)
        )
        Spacer(Modifier.width(7.dp))
        Text(
            text,
            fontWeight = FontWeight.SemiBold,
            fontSize = if (cover) 13.sp else 15.sp,
            color = if (status == VpnController.Status.idle) Color(0xFF6B7280) else color,
        )
    }
}

@Composable
fun BashCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val fold = LocalFold.current
    Column(
        modifier
            .shadow(if (fold.isCover) 6.dp else 10.dp, RoundedCornerShape(fold.cardRadius), clip = false)
            .clip(RoundedCornerShape(fold.cardRadius))
            .background(BashXTheme.card)
            .padding(fold.cardPad)
            .fillMaxWidth()
    ) { content() }
}

@Composable
fun PageBackground(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier
            .background(
                Brush.verticalGradient(
                    listOf(BashXTheme.accentBright.copy(alpha = 0.22f), BashXTheme.grouped)
                )
            )
    ) { content() }
}

@Composable
fun BrandMark(size: Dp = LocalFold.current.brandSize, corner: Dp = LocalFold.current.brandCorner) {
    Image(
        painter = painterResource(R.drawable.brand_mark),
        contentDescription = "BashX",
        modifier = Modifier
            .size(size)
            .shadow(10.dp, RoundedCornerShape(corner), clip = false)
            .clip(RoundedCornerShape(corner)),
    )
}

@Composable
fun FoldButtonModifier(): Modifier {
    val fold = LocalFold.current
    return Modifier
        .fillMaxWidth()
        .defaultMinSize(minHeight = fold.buttonHeight)
}
