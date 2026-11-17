package com.voiceshift.vr.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.voiceshift.dsp.VoiceParameter
import com.voiceshift.vr.ui.theme.NumericStyle
import com.voiceshift.vr.ui.theme.VsColors
import kotlin.math.roundToInt

@Composable
fun SectionCard(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.titleMedium)
                    if (subtitle != null) {
                        Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                trailing?.invoke()
            }
            content()
        }
    }
}

/** Horizontal level meter: RMS bar (green -> amber -> red) with a peak marker, -60..0 dBFS. */
@Composable
fun LevelMeter(label: String, rmsDb: Float, peakDb: Float, modifier: Modifier = Modifier) {
    val floor = -60f
    fun norm(db: Float) = ((db - floor) / -floor).coerceIn(0f, 1f)
    Column(modifier.semantics { contentDescription = "$label level ${rmsDb.roundToInt()} dB" }) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                if (peakDb <= -119f) "—" else "${"%.0f".format(rmsDb)} / ${"%.0f".format(peakDb)} dB",
                style = NumericStyle,
                color = if (peakDb > -1.5f) VsColors.Red else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(4.dp))
        Canvas(Modifier.fillMaxWidth().height(14.dp)) {
            val radius = CornerRadius(size.height / 2, size.height / 2)
            drawRoundRect(color = VsColors.SurfaceHigh, cornerRadius = radius)
            val w = size.width * norm(rmsDb)
            if (w > 0f) {
                drawRoundRect(
                    brush = Brush.horizontalGradient(
                        0f to VsColors.Green, 0.7f to VsColors.Amber, 1f to VsColors.Red,
                        startX = 0f, endX = size.width,
                    ),
                    size = Size(w, size.height),
                    cornerRadius = radius,
                )
            }
            val px = size.width * norm(peakDb)
            if (peakDb > floor) {
                drawLine(Color.White, Offset(px, 0f), Offset(px, size.height), strokeWidth = 3f)
            }
        }
    }
}

/** Slider bound to a [VoiceParameter] range with a formatted value readout. */
@Composable
fun ParameterSlider(
    parameter: VoiceParameter,
    value: Float,
    onChange: (Float) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    label: String = parameter.label,
) {
    Column(modifier) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            Text(formatParameter(parameter, value), style = NumericStyle, color = MaterialTheme.colorScheme.primary)
        }
        Slider(
            value = value,
            onValueChange = onChange,
            valueRange = parameter.min..parameter.max,
            enabled = enabled,
            modifier = Modifier.semantics { contentDescription = "$label ${formatParameter(parameter, value)}" },
        )
    }
}

fun formatParameter(parameter: VoiceParameter, value: Float): String = when (parameter) {
    VoiceParameter.PITCH_SEMITONES, VoiceParameter.FORMANT_SEMITONES ->
        "%+.1f st".format(value)
    VoiceParameter.NOISE_REDUCTION, VoiceParameter.COMPRESSION, VoiceParameter.BREATHINESS ->
        "${(value * 100).roundToInt()} %"
    VoiceParameter.GATE_THRESHOLD_DB -> if (value <= -79.9f) "off" else "%.0f dB".format(value)
    VoiceParameter.LOW_CUT_HZ -> "%.0f Hz".format(value)
    VoiceParameter.AGC_ENABLED -> if (value >= 0.5f) "on" else "off"
    else -> "%+.1f dB".format(value)
}

@Composable
fun SwitchRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, subtitle: String? = null, enabled: Boolean = true) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Spacer(Modifier.width(12.dp))
        Switch(checked = checked, onCheckedChange = onChange, enabled = enabled)
    }
}

@Composable
fun StatusPill(text: String, color: Color, modifier: Modifier = Modifier) {
    Row(
        modifier
            .background(color.copy(alpha = 0.15f), RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(8.dp).background(color, CircleShape))
        Spacer(Modifier.width(6.dp))
        Text(text, style = MaterialTheme.typography.labelMedium, color = color, fontWeight = FontWeight.SemiBold)
    }
}

enum class NoticeKind(val color: Color, val icon: ImageVector) {
    INFO(VsColors.Violet, Icons.Filled.Info),
    OK(VsColors.Green, Icons.Filled.CheckCircle),
    WARN(VsColors.Amber, Icons.Filled.Warning),
    ERROR(VsColors.Red, Icons.Filled.Warning),
}

@Composable
fun Notice(kind: NoticeKind, text: String, modifier: Modifier = Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            .background(kind.color.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
            .padding(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(kind.icon, contentDescription = null, tint = kind.color, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(10.dp))
        Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface)
    }
}

@Composable
fun StatRow(label: String, value: String, valueColor: Color = Color.Unspecified) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
        Text(value, style = NumericStyle, color = if (valueColor == Color.Unspecified) MaterialTheme.colorScheme.onSurface else valueColor)
    }
}
