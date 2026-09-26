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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.R
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
            title = stringResource(R.string.devices_title),
            subtitle = stringResource(R.string.devices_subtitle),
        )
        if (state.devicesLoading) {
            LoadingBox()
            return
        }
        if (state.devices.isEmpty()) {
            EmptyBox(stringResource(R.string.devices_empty))
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
                                stringResource(
                                    R.string.devices_title_format,
                                    d.device.ifBlank { stringResource(R.string.devices_unnamed) },
                                    d.short,
                                ),
                                style = MaterialTheme.typography.titleMedium,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                            Text(
                                stringResource(R.string.devices_created_format, d.created),
                                fontSize = 13.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                stringResource(R.string.devices_expires_format, d.expires),
                                fontSize = 13.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        TextButton(onClick = { vm.revokeDevice(d.id) }) { Text(stringResource(R.string.devices_remove)) }
                    }
                }
            }
        }
    }
}
