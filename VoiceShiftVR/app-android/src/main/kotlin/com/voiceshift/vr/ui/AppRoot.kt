package com.voiceshift.vr.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Face
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import com.voiceshift.vr.session.VoiceSession
import com.voiceshift.vr.ui.dashboard.DashboardScreen
import com.voiceshift.vr.ui.devices.DevicesScreen
import com.voiceshift.vr.ui.models.ModelsScreen
import com.voiceshift.vr.ui.settings.SettingsScreen
import com.voiceshift.vr.ui.voice.VoiceScreen
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

enum class Tab(val label: String, val icon: ImageVector) {
    DASHBOARD("Home", Icons.Filled.Home),
    VOICE("Voice", Icons.Filled.Face),
    MODELS("Models", Icons.Filled.Star),
    DEVICES("Devices", Icons.Filled.Build),
    SETTINGS("Settings", Icons.Filled.Settings),
}

@HiltViewModel
class AppViewModel @Inject constructor(session: VoiceSession) : ViewModel() {
    val messages = session.messages
}

@Composable
fun AppRoot(vm: AppViewModel = hiltViewModel()) {
    var tab by rememberSaveable { mutableStateOf(Tab.DASHBOARD) }
    val snackbar = remember { SnackbarHostState() }
    LaunchedEffect(Unit) { vm.messages.collect { snackbar.showSnackbar(it) } }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                Tab.entries.forEach { t ->
                    NavigationBarItem(
                        selected = t == tab,
                        onClick = { tab = t },
                        icon = { Icon(t.icon, contentDescription = null) },
                        label = { Text(t.label) },
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (tab) {
                Tab.DASHBOARD -> DashboardScreen(onOpenModels = { tab = Tab.MODELS }, onOpenDevices = { tab = Tab.DEVICES })
                Tab.VOICE -> VoiceScreen()
                Tab.MODELS -> ModelsScreen()
                Tab.DEVICES -> DevicesScreen()
                Tab.SETTINGS -> SettingsScreen()
            }
        }
    }
}
