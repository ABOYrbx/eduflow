package de.eduflow.android.ui.settings

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.data.TokenStore
import de.eduflow.android.data.dto.SettingsDefaults
import de.eduflow.android.ui.common.AvatarDot
import de.eduflow.android.ui.common.EduCard
import de.eduflow.android.ui.common.FilterChips
import de.eduflow.android.ui.common.LoadingBox
import de.eduflow.android.ui.common.PrimaryButton
import de.eduflow.android.ui.common.ScreenHead
import de.eduflow.android.ui.common.SectionLabel
import de.eduflow.android.ui.common.StatusPill
import de.eduflow.android.ui.theme.Accents

/**
 * „Neue Nachrichten"-Schalter (Paket F): rein lokal, kein Server-Key
 * (kein Push — Nicht-Ziel). Eigene Prefs, damit Paket 0 (TokenStore)
 * eingefroren bleibt.
 */
private object NotifyPrefs {
    private const val FILE = "eduflow_prefs"
    private const val KEY = "notify_news"

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean(KEY, true)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY, enabled).apply()
    }
}

/**
 * Einstellungen-Screen (Paket F, Redesign-PNG Screen 05).
 *
 * Titel + „Dein EduFlow-Konto", Profil-Karte (Avatar, Name,
 * „Schule · verbunden"), Sektion DARSTELLUNG (Erscheinungsbild
 * Hell/Dunkel/System als Radio-Zeilen + System-Pill, Akzentfarbe mit
 * Farb-Dots), Sektion BENACHRICHTIGUNGEN (Schalter „Neue Nachrichten"),
 * Sektion WETTER (Karte an/aus + Stadt, Speichern via PUT settings),
 * Sektion KONTO & SICHERHEIT (Verbundene Geräte + Anzahl, Datenschutz,
 * Abmelden rot). Server-URL und Cache leeren leben im Mehr-Tab.
 */
@Composable
fun SettingsScreen(
    vm: SettingsViewModel,
    baseUrl: String,
    isDemo: Boolean = false,
    onBaseUrlChange: (String) -> Unit,
    onDevices: () -> Unit,
    onLogout: () -> Unit,
    onRestartOnboarding: () -> Unit = {},
    onSessionExpired: () -> Unit = onLogout,
    onSettingsSaved: () -> Unit = {},
) {
    val state by vm.state.collectAsState()
    val themeChoice by vm.themeChoice.collectAsState()
    val accentKey by vm.accentKey.collectAsState()
    val developerOptions by vm.developerOptions.collectAsState()
    val session by vm.session.collectAsState()
    val context = LocalContext.current
    var baseDraft by remember(baseUrl) { mutableStateOf(baseUrl) }
    var notifyNews by remember { mutableStateOf(NotifyPrefs.isEnabled(context)) }
    var showPrivacy by remember { mutableStateOf(false) }
    var saveStateObserved by remember { mutableStateOf(false) }

    // Frisch laden beim Öffnen (VM wird im NavGraph eager erzeugt,
    // ggf. noch ohne Token geladen).
    LaunchedEffect(Unit) {
        vm.reload()
        vm.reloadDevices()
    }
    LaunchedEffect(state.saved) {
        if (state.saved && saveStateObserved) onSettingsSaved()
        if (!state.saved) saveStateObserved = true
    }

    // 401-Verhalten (→ Login): Sitzung ist geleert, weiter zum Login.
    if (state.sessionExpired) {
        LaunchedEffect(Unit) { onSessionExpired() }
        LoadingBox()
        return
    }

    if (state.loading) {
        LoadingBox()
        return
    }
    // Fehler zeigen, aber nie in eine Sackgasse führen: Gerade bei falscher
    // Server-URL muss man sie hier korrigieren oder sich abmelden können.
    state.error?.let { msg ->
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            ScreenHead(title = "Einstellungen", subtitle = "Dein EduFlow-Konto")
            Text(msg, color = MaterialTheme.colorScheme.error)
            PrimaryButton(text = "Erneut versuchen", onClick = { vm.reload() })
            if (isDemo) {
                SectionLabel("Demo-Modus")
                Text("Es werden ausschließlich synthetische Beispieldaten vom lokalen Demo-Server geladen.")
            } else {
                SectionLabel("Server")
                SettingsField(
                    value = baseDraft,
                    onValueChange = { baseDraft = it },
                    placeholder = "Server (…/api/v1/)",
                )
                PrimaryButton(
                    text = "Server übernehmen",
                    onClick = { onBaseUrlChange(baseDraft.trim().trimEnd('/')); vm.reload() },
                )
            }
            TextButton(onClick = { vm.logout(onLogout) }) {
                Text("Abmelden", color = MaterialTheme.colorScheme.error)
            }
        }
        return
    }

    val v = state.values
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ScreenHead(title = "Einstellungen", subtitle = "Dein EduFlow-Konto")

        EduCard(modifier = Modifier.fillMaxWidth()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(16.dp),
            ) {
                AvatarDot(initials = initialsOf(session.username.ifBlank { "–" }))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        session.username.ifBlank { "–" },
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        "${session.subdomain.ifBlank { "Schule" }} · verbunden",
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        SectionLabel("Darstellung")
        EduCard(modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                AppearanceRow(
                    title = "Hell",
                    subtitle = "Immer helles Design",
                    selected = themeChoice == TokenStore.THEME_LIGHT,
                    onClick = { vm.setTheme(TokenStore.THEME_LIGHT) },
                )
                AppearanceRow(
                    title = "Dunkel",
                    subtitle = "Immer dunkles Design",
                    selected = themeChoice == TokenStore.THEME_DARK,
                    onClick = { vm.setTheme(TokenStore.THEME_DARK) },
                )
                AppearanceRow(
                    title = "System",
                    subtitle = "Folgt Hell/Dunkel des Geräts",
                    selected = themeChoice == TokenStore.THEME_SYSTEM,
                    onClick = { vm.setTheme(TokenStore.THEME_SYSTEM) },
                    pill = "System",
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    "Akzentfarbe",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Spacer(Modifier.height(8.dp))
                AccentDotsRow(selected = accentKey, onSelect = vm::setAccent)
            }
        }

        SectionLabel("Benachrichtigungen")
        EduCard(modifier = Modifier.fillMaxWidth()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(16.dp),
            ) {
                Text(
                    "Neue Nachrichten",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f),
                )
                Switch(
                    checked = notifyNews,
                    onCheckedChange = {
                        notifyNews = it
                        NotifyPrefs.setEnabled(context, it)
                    },
                )
            }
        }

        SectionLabel("Übersicht & Aufgaben")
        EduCard(modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                Text(
                    "Startseite nach Anmeldung",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Spacer(Modifier.height(8.dp))
                FilterChips(
                    options = SettingsDefaults.LANDING_OPTIONS.map {
                        landingLabels[it] ?: it
                    },
                    selected = landingLabels[v.landing] ?: v.landing,
                    onSelect = { label ->
                        landingLabels.entries.firstOrNull { it.value == label }?.let {
                            vm.update(v.copy(landing = it.key))
                        }
                    },
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    "Aufgaben: Standardfilter",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Spacer(Modifier.height(8.dp))
                FilterChips(
                    options = SettingsDefaults.HW_STATUS_OPTIONS.map {
                        hwStatusLabels[it] ?: it
                    },
                    selected = hwStatusLabels[v.hwStatus] ?: v.hwStatus,
                    onSelect = { label ->
                        hwStatusLabels.entries.firstOrNull { it.value == label }?.let {
                            vm.update(v.copy(hwStatus = it.key))
                        }
                    },
                )
                Spacer(Modifier.height(12.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "Tests und Prüfungen einbeziehen",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.weight(1f),
                    )
                    Switch(
                        checked = v.hwTests,
                        onCheckedChange = { vm.update(v.copy(hwTests = it)) },
                    )
                }
                Spacer(Modifier.height(8.dp))
                var unread by remember(v.ovUnread) { mutableStateOf(v.ovUnread.toString()) }
                SettingsField(
                    value = unread,
                    onValueChange = {
                        unread = it
                        it.toIntOrNull()?.let { n ->
                            vm.update(v.copy(ovUnread = n.coerceIn(1, 50)))
                        }
                    },
                    placeholder = "Max. ungelesene Nachrichten (1–50)",
                )
                Spacer(Modifier.height(8.dp))
                var homework by remember(v.ovHomework) { mutableStateOf(v.ovHomework.toString()) }
                SettingsField(
                    value = homework,
                    onValueChange = {
                        homework = it
                        it.toIntOrNull()?.let { n ->
                            vm.update(v.copy(ovHomework = n.coerceIn(1, 50)))
                        }
                    },
                    placeholder = "Max. offene Hausaufgaben (1–50)",
                )
            }
        }

        SectionLabel("Wetter")
        EduCard(modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                var city by remember(v.wetterCity) { mutableStateOf(v.wetterCity) }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "Wetterkarte anzeigen",
                            fontSize = 15.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                        Text(
                            "Auf der Übersicht in Android und im Web",
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Switch(
                        checked = v.ovWetter,
                        onCheckedChange = { vm.update(v.copy(ovWetter = it)) },
                    )
                }
                Spacer(Modifier.height(8.dp))
                SettingsField(
                    value = city,
                    onValueChange = {
                        city = it
                        val query = it.replace("\n", " ").replace("\r", "")
                            .trim().take(SettingsDefaults.WETTER_CITY_MAX)
                        vm.update(
                            v.copy(
                                wetterCity = query,
                            ),
                        )
                        vm.searchWeatherCities(query)
                    },
                    placeholder = "Stadt für Wetterkarte (z. B. Berlin)",
                )
                if (state.weatherCitySearchLoading) {
                    Text("Städte werden gesucht …", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                state.weatherCitySearchError?.let {
                    Text(it, fontSize = 12.sp, color = MaterialTheme.colorScheme.error)
                }
                if (state.weatherCitySearchComplete && state.weatherCitySuggestions.isEmpty()
                    && state.weatherCitySearchError == null
                ) {
                    Text("Keine passenden Orte gefunden.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                state.weatherCitySuggestions.forEach { suggestion ->
                    Surface(
                        color = MaterialTheme.colorScheme.surfaceContainerLow,
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth().clickable {
                            city = suggestion.query
                            vm.update(v.copy(wetterCity = suggestion.query))
                        },
                    ) {
                        Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
                            Text(
                                suggestion.name,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                            val placeDetail = listOf(suggestion.state, suggestion.country)
                                .filter { it.isNotBlank() }.joinToString(", ")
                            if (placeDetail.isNotBlank()) {
                                Text(
                                    placeDetail,
                                    fontSize = 12.sp,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
                Text(
                    "Der Ort wird für die Wetterkarte auf Android und im Web verwendet.",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(8.dp))
                PrimaryButton(text = "Speichern", onClick = { vm.save() })
                if (state.saved) {
                    Text(
                        "Gespeichert.",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        SectionLabel("Konto & Sicherheit")
        EduCard(modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.fillMaxWidth()) {
                val count = state.devices.size
                AccountRow(
                    title = "Verbundene Geräte",
                    trailing = "$count ${if (count == 1) "Gerät" else "Geräte"}",
                    onClick = onDevices,
                )
                AccountRow(
                    title = "Datenschutz",
                    onClick = { showPrivacy = true },
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                        .clickable { vm.logout(onLogout) }
                        .padding(16.dp),
                ) {
                    Text(
                        "Abmelden",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        }

        SectionLabel("Entwickleroptionen")
        EduCard(modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f).padding(end = 12.dp)) {
                        Text("Entwickleroptionen aktivieren", fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface)
                        Text("Zusätzliche Diagnose- und Testaktionen anzeigen.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Switch(checked = developerOptions, onCheckedChange = vm::setDeveloperOptions)
                }
                if (developerOptions) {
                    Spacer(Modifier.height(10.dp))
                    androidx.compose.material3.HorizontalDivider()
                    Spacer(Modifier.height(10.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f).padding(end = 12.dp)) {
                            Text("Onboarding erneut durchlaufen", fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface)
                            Text("Meldet dich ab und startet die Einführung neu.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Switch(checked = false, onCheckedChange = { checked -> if (checked) vm.restartOnboarding(onRestartOnboarding) })
                    }
                }
            }
        }
        Spacer(Modifier.height(88.dp))
    }

    if (showPrivacy) {
        AlertDialog(
            onDismissRequest = { showPrivacy = false },
            title = { Text("Datenschutz") },
            text = {
                Text(
                    "Deine Zugangsdaten bleiben auf diesem Gerät. Auf dem Server " +
                        "landen nur kurzzeitige Caches und widerrufbare Tokens — " +
                        "kein Tracking, keine Weitergabe an Dritte.",
                )
            },
            confirmButton = {
                TextButton(onClick = { showPrivacy = false }) { Text("OK") }
            },
        )
    }
}

/** Erscheinungsbild-Zeile: Radio + Titel/Sub (+ System-Pill). */
@Composable
private fun AppearanceRow(
    title: String,
    subtitle: String,
    selected: Boolean,
    onClick: () -> Unit,
    pill: String? = null,
) {
    val scheme = MaterialTheme.colorScheme
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        RadioButton(selected = selected, onClick = onClick)
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Bold, color = scheme.onSurface)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
            )
        }
        if (pill != null) {
            StatusPill(text = pill, dot = scheme.primary)
        }
    }
}

/** Konto-Zeile: Titel + optionale Anzahl + Chevron. */
@Composable
private fun AccountRow(
    title: String,
    trailing: String? = null,
    onClick: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(16.dp),
    ) {
        Text(
            title,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            color = scheme.onSurface,
            modifier = Modifier.weight(1f),
        )
        if (trailing != null) {
            Text(
                trailing,
                fontSize = 13.sp,
                color = scheme.onSurfaceVariant,
            )
            Spacer(Modifier.width(4.dp))
        }
        Icon(
            Icons.Filled.ChevronRight,
            contentDescription = null,
            tint = scheme.onSurfaceVariant,
        )
    }
}

/** Textfeld im Karten-Stil (16dp Radius, wie Verfassen/Antwort). */
@Composable
private fun SettingsField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder) },
        modifier = modifier.fillMaxWidth(),
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

/**
 * Akzent-Dots wie im Web (.accent-dots.set-accents, 26px, aktiver Ring).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AccentDotsRow(
    selected: String,
    onSelect: (String) -> Unit,
) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Accents.forEach { opt ->
            val isSel = opt.key == selected
            Box(
                modifier = Modifier.size(26.dp)
                    .border(
                        width = if (isSel) 2.dp else 1.dp,
                        color = if (isSel) MaterialTheme.colorScheme.onSurface
                        else MaterialTheme.colorScheme.outline,
                        shape = CircleShape,
                    )
                    .clip(CircleShape)
                    .background(opt.color)
                    .clickable { onSelect(opt.key) },
            )
        }
    }
}

private fun initialsOf(name: String): String =
    name.split(" ", " ").mapNotNull { it.firstOrNull()?.toString() }.take(2).joinToString("")

/** Deutsche Labels für die Server-Keys (Startseite, Aufgabenfilter). */
private val landingLabels = mapOf(
    "uebersicht" to "Übersicht",
    "dashboard" to "Nachrichten",
    "hausaufgaben" to "Aufgaben",
    "noten" to "Noten",
    "stundenplan" to "Plan",
)

private val hwStatusLabels = mapOf(
    "alle" to "Alle",
    "offen" to "Offen",
    "überfällig" to "Überfällig",
    "erledigt" to "Erledigt",
    "papierkorb" to "Papierkorb",
)
