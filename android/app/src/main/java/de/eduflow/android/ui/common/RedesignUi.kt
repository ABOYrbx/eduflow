package de.eduflow.android.ui.common

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.R
import de.eduflow.android.data.Session

/**
 * Redesign-Komponenten aus templates/EduFlow · Weitere App Screens.png
 * (Paket 0, eingefroren). Alte Screens nutzen weiter CommonUi.kt, bis
 * sie in den Paketen A–G umgebaut werden.
 */

val LocalEduFlowSession = staticCompositionLocalOf { Session() }

/** Kopfzeile: E-Logo + „EduFlow" links, Profilmenü rechts. */
@Composable
fun AppHeader(
    onSettings: () -> Unit,
    onLogout: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var menuOpen by remember { mutableStateOf(false) }
    val scheme = MaterialTheme.colorScheme
    val session = LocalEduFlowSession.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier.fillMaxWidth(),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(28.dp)
                .clip(RoundedCornerShape(8.dp)),
        ) {
            Image(
                painter = painterResource(id = R.drawable.logo),
                contentDescription = "EduFlow-Logo",
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(28.dp),
            )
        }
        Text(
            "EduFlow",
            fontWeight = FontWeight.Bold,
            fontSize = 16.sp,
            color = scheme.onBackground,
            modifier = Modifier.padding(start = 8.dp).weight(1f),
        )
        if (session.isDemo) {
            Surface(
                shape = CircleShape,
                color = scheme.secondaryContainer,
                modifier = Modifier.padding(end = 8.dp),
            ) {
                Text(
                    "DEMO",
                    color = scheme.onSecondaryContainer,
                    fontWeight = FontWeight.Bold,
                    fontSize = 10.sp,
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                )
            }
        }
        Box {
            IconButton(onClick = { menuOpen = true }) {
                Surface(
                    shape = CircleShape,
                    color = scheme.primary,
                    modifier = Modifier.size(36.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(
                            session.username.firstOrNull()?.uppercase() ?: "?",
                            color = scheme.onPrimary,
                            fontWeight = FontWeight.Bold,
                            fontSize = 14.sp,
                        )
                    }
                }
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                    Text("Dein Profil", fontWeight = FontWeight.SemiBold)
                    Text(
                        "${session.username.ifBlank { "Konto" }} @ ${session.subdomain.ifBlank { "EduPage" }}",
                        color = scheme.onSurfaceVariant,
                        fontSize = 12.sp,
                    )
                }
                androidx.compose.material3.HorizontalDivider()
                DropdownMenuItem(
                    text = { Text("Einstellungen") },
                    onClick = { menuOpen = false; onSettings() },
                )
                DropdownMenuItem(
                    text = { Text("Abmelden") },
                    onClick = { menuOpen = false; onLogout() },
                )
            }
        }
    }
}

/** Screen-Kopf: fetter Titel + grauer Untertitel (wie im PNG). */
@Composable
fun ScreenHead(
    title: String,
    subtitle: String,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    Column(modifier = modifier) {
        Text(
            title,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color = scheme.onBackground,
        )
        Text(
            subtitle,
            style = MaterialTheme.typography.bodyMedium,
            color = scheme.onSurfaceVariant,
        )
    }
}

/** Kapitälchen-Sektionslabel („4 OFFEN · 1 ÜBERFÄLLIG", „FÄCHER", …). */
@Composable
fun SectionLabel(
    text: String,
    modifier: Modifier = Modifier,
) {
    Text(
        text.uppercase(),
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 1.2.sp,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier,
    )
}

/** Karte: 16dp Radius, 1dp Rahmen (wie im PNG). */
@Composable
fun EduCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val clickableMod = if (onClick != null) {
        modifier.clip(MaterialTheme.shapes.medium).clickable(onClick = onClick)
    } else {
        modifier
    }
    Card(
        modifier = clickableMod,
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        content = { content() },
    )
}

/** Suche als Pille mit Lupen-Icon (wie im PNG). */
@Composable
fun SearchPill(
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
        leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
        singleLine = true,
        shape = CircleShape,
        textStyle = MaterialTheme.typography.bodyMedium,
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = scheme.surface,
            unfocusedContainerColor = scheme.surface,
            unfocusedBorderColor = scheme.outlineVariant,
            focusedBorderColor = scheme.primary,
            cursorColor = scheme.primary,
        ),
        modifier = modifier.fillMaxWidth(),
    )
}

/** Filter-Chips in einer Zeile (aktiv = invertiert, wie im PNG). */
@Composable
fun FilterChips(
    options: List<String>,
    selected: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = modifier.horizontalScroll(rememberScrollState()),
    ) {
        options.forEach { opt ->
            val active = opt == selected
            Surface(
                shape = CircleShape,
                color = if (active) scheme.primary else scheme.surface,
                border = if (active) {
                    null
                } else {
                    BorderStroke(1.dp, scheme.outlineVariant)
                },
                modifier = Modifier.clip(CircleShape).clickable { onSelect(opt) },
            ) {
                Text(
                    opt,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (active) scheme.onPrimary else scheme.onSurface,
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
                )
            }
        }
    }
}

/** Status-Pill: farbiger Hintergrund (12 % Deckkraft), 10sp Kapitälchen. */
@Composable
fun StatusPill(
    text: String,
    dot: Color,
    modifier: Modifier = Modifier,
) {
    Surface(
        shape = CircleShape,
        color = dot.copy(alpha = 0.14f),
        modifier = modifier,
    ) {
        Text(
            text.uppercase(),
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold,
            color = dot,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
        )
    }
}

/** Primär-Button: 52dp hoch, volle Breite, Pill (wie im PNG). */
@Composable
fun PrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val scheme = MaterialTheme.colorScheme
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = scheme.primary,
            contentColor = scheme.onPrimary,
            disabledContainerColor = scheme.surfaceVariant,
            disabledContentColor = scheme.onSurfaceVariant,
        ),
        modifier = modifier.fillMaxWidth().height(52.dp),
    ) {
        Text(text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** Avatar-Kreis mit Initialen (40dp, wie im PNG). */
@Composable
fun AvatarDot(
    initials: String,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier.size(40.dp)
            .clip(CircleShape)
            .background(scheme.surfaceVariant),
    ) {
        Text(
            initials.take(2).uppercase(),
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            color = scheme.onSurfaceVariant,
        )
    }
}
