package de.eduflow.android.ui.more

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Cached
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Grade
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.EventNote
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.ui.common.EduCard
import de.eduflow.android.ui.common.ScreenHead
import de.eduflow.android.ui.settings.SettingsViewModel

/**
 * Mehr-Tab (Paket F, Redesign-PNG Screen 05 als Sammelstelle):
 * Noten, Einstellungen, Geräte, Server-URL, Cache leeren, Abmelden.
 */
@Composable
fun MoreScreen(
    onGrades: () -> Unit,
    onSchool: () -> Unit = {},
    onSettings: () -> Unit,
    onDevices: () -> Unit,
    onLogout: () -> Unit,
    vm: SettingsViewModel? = null,
    baseUrl: String = "",
    isDemo: Boolean = false,
    onBaseUrlChange: (String) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val cleared = if (vm != null) {
        val s by vm.state.collectAsState()
        s.cleared
    } else {
        null
    }
    var showServer by remember { mutableStateOf(false) }
    var serverDraft by remember(baseUrl) { mutableStateOf(baseUrl) }

    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = modifier.fillMaxSize()
            .verticalScroll(rememberScrollState()).padding(16.dp),
    ) {
        ScreenHead(title = "Mehr", subtitle = "Weitere Bereiche")
        MoreRow(
            icon = Icons.Filled.EventNote,
            title = "Termine & Vertretungen",
            subtitle = "Prüfungen, Schulereignisse und Änderungen",
            onClick = onSchool,
        )
        MoreRow(
            icon = Icons.Filled.Grade,
            title = "Noten",
            subtitle = "Deine Leistungen nach Fach",
            onClick = onGrades,
        )
        MoreRow(
            icon = Icons.Filled.Settings,
            title = "Einstellungen",
            subtitle = "Darstellung, Konto und Server",
            onClick = onSettings,
        )
        MoreRow(
            icon = Icons.Filled.PhoneAndroid,
            title = "Geräte",
            subtitle = "Angemeldete Geräte verwalten",
            onClick = onDevices,
        )
        if (isDemo) {
            MoreRow(
                icon = Icons.Filled.Dns,
                title = "Demo-Modus",
                subtitle = "Nur Beispieldaten · keine echten Schulverbindungen",
                onClick = {},
            )
        } else {
            MoreRow(
                icon = Icons.Filled.Dns,
                title = "Server-URL",
                subtitle = baseUrl.ifBlank { "Server für API-Anfragen" },
                onClick = {
                    serverDraft = baseUrl
                    showServer = true
                },
            )
        }
        MoreRow(
            icon = Icons.Filled.Cached,
            title = "Cache leeren",
            subtitle = cleared?.let { "$cleared Datei(en) gelöscht" }
                ?: "Zwischengespeicherte Daten löschen",
            onClick = { vm?.clearCache() },
        )
        MoreRow(
            icon = Icons.AutoMirrored.Filled.Logout,
            title = "Abmelden",
            subtitle = "Von diesem Gerät abmelden",
            onClick = onLogout,
            destructive = true,
        )
    }

    if (showServer) {
        val scheme = MaterialTheme.colorScheme
        AlertDialog(
            onDismissRequest = { showServer = false },
            title = { Text("Server-URL") },
            text = {
                Column {
                    Text(
                        "Server für API-Anfragen (…/api/v1/).",
                        fontSize = 13.sp,
                        color = scheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = serverDraft,
                        onValueChange = { serverDraft = it },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        shape = RoundedCornerShape(16.dp),
                        textStyle = MaterialTheme.typography.bodyMedium,
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedContainerColor = scheme.surface,
                            unfocusedContainerColor = scheme.surface,
                            unfocusedBorderColor = scheme.outlineVariant,
                            focusedBorderColor = scheme.primary,
                            cursorColor = scheme.primary,
                        ),
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    onBaseUrlChange(serverDraft.trim().trimEnd('/'))
                    showServer = false
                }) { Text("Übernehmen") }
            },
            dismissButton = {
                TextButton(onClick = { showServer = false }) { Text("Abbrechen") }
            },
        )
    }
}

@Composable
private fun MoreRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
    destructive: Boolean = false,
) {
    val scheme = MaterialTheme.colorScheme
    EduCard(
        modifier = Modifier.fillMaxWidth()
            .clip(MaterialTheme.shapes.medium)
            .clickable(onClick = onClick),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(16.dp),
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = if (destructive) scheme.error else scheme.onSurfaceVariant,
            )
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Text(
                    title,
                    fontWeight = FontWeight.SemiBold,
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (destructive) scheme.error else scheme.onSurface,
                )
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.onSurfaceVariant,
                )
            }
            Icon(
                Icons.Filled.ChevronRight,
                contentDescription = null,
                tint = scheme.onSurfaceVariant,
            )
        }
    }
}
