package de.eduflow.android.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.ui.common.EduCard
import de.eduflow.android.ui.common.EmptyBox
import de.eduflow.android.ui.common.LoadingBox
import de.eduflow.android.ui.common.ScreenHead

/**
 * Eigene Tokens (ohne Secrets) + gezieltes Widerrufen — wie /einstellungen
 * im Web (Paket F, Redesign-PNG Screen 05: „Verbundene Geräte").
 */
@Composable
fun DevicesScreen(
    vm: SettingsViewModel,
    onSessionExpired: (() -> Unit)? = null,
) {
    val state by vm.state.collectAsState()

    LaunchedEffect(Unit) { vm.reloadDevices() }

    // 401-Verhalten (→ Login): Sitzung ist geleert, weiter zum Login.
    if (state.sessionExpired) {
        LaunchedEffect(Unit) { onSessionExpired?.invoke() }
        LoadingBox()
        return
    }
    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        ScreenHead(
            title = "Geräte",
            subtitle = "Angemeldete Geräte verwalten",
        )
        if (state.devicesLoading) {
            LoadingBox()
            return
        }
        if (state.devices.isEmpty()) {
            EmptyBox("Keine weiteren Geräte angemeldet.")
            return
        }
        LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(state.devices, key = { it.id }) { d ->
                EduCard(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                d.device.ifBlank { "Unbenanntes Gerät" } + " (${d.short})",
                                style = MaterialTheme.typography.titleMedium,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                            Text(
                                "Erstellt: ${d.created}",
                                fontSize = 13.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                "Läuft ab: ${d.expires}",
                                fontSize = 13.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        TextButton(onClick = { vm.revokeDevice(d.id) }) { Text("Entfernen") }
                    }
                }
            }
        }
    }
}
