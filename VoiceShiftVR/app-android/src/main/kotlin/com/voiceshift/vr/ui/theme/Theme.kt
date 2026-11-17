package com.voiceshift.vr.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

object VsColors {
    val Background = Color(0xFF0E0F14)
    val Surface = Color(0xFF171923)
    val SurfaceHigh = Color(0xFF20232F)
    val Outline = Color(0xFF2E3242)
    val Pink = Color(0xFFFF6FB5)
    val Violet = Color(0xFF8B7CFF)
    val Teal = Color(0xFF4FD1C5)
    val Amber = Color(0xFFFFC857)
    val Red = Color(0xFFFF5A6E)
    val Green = Color(0xFF5BD68A)
    val TextPrimary = Color(0xFFECEEF5)
    val TextSecondary = Color(0xFFA3A8BC)
}

private val colorScheme = darkColorScheme(
    primary = VsColors.Pink,
    onPrimary = Color(0xFF2B0A1D),
    primaryContainer = Color(0xFF4A1B36),
    onPrimaryContainer = Color(0xFFFFD8EA),
    secondary = VsColors.Violet,
    onSecondary = Color(0xFF140D3A),
    secondaryContainer = Color(0xFF2C2560),
    onSecondaryContainer = Color(0xFFE4DFFF),
    tertiary = VsColors.Teal,
    onTertiary = Color(0xFF00201D),
    background = VsColors.Background,
    onBackground = VsColors.TextPrimary,
    surface = VsColors.Surface,
    onSurface = VsColors.TextPrimary,
    surfaceVariant = VsColors.SurfaceHigh,
    onSurfaceVariant = VsColors.TextSecondary,
    surfaceContainer = VsColors.Surface,
    surfaceContainerHigh = VsColors.SurfaceHigh,
    surfaceContainerLow = Color(0xFF13141C),
    outline = VsColors.Outline,
    outlineVariant = Color(0xFF262A38),
    error = VsColors.Red,
    onError = Color(0xFF2D0006),
)

private val base = Typography()

private val typography = base.copy(
    headlineSmall = base.headlineSmall.copy(fontWeight = FontWeight.SemiBold),
    titleLarge = base.titleLarge.copy(fontWeight = FontWeight.SemiBold),
    titleMedium = base.titleMedium.copy(fontWeight = FontWeight.SemiBold),
    labelSmall = base.labelSmall.copy(letterSpacing = 0.4.sp),
)

/** Monospace numbers so meters and stats do not jitter while updating. */
val NumericStyle = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 13.sp)

@Composable
fun VoiceShiftTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = colorScheme, typography = typography, content = content)
}
