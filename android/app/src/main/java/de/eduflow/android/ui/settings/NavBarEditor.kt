package de.eduflow.android.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.R
import de.eduflow.android.ui.navigation.NavTabs

/**
 * Editor für die Navigationsleisten-Belegung: Häkchen wählen bis zu
 * [NavTabs.MAX_CONTENT] Bereiche, Pfeile sortieren um (reine
 * Umordnung/Auswahl via [NavTabs], Speichern bleibt beim Aufrufer).
 * „Mehr“ ist fest angepinnt und erscheint hier nicht.
 */
@Composable
fun NavBarEditor(
    selected: List<String>,
    onSelectionChange: (List<String>) -> Unit,
    modifier: Modifier = Modifier,
) {
    val unselected = NavTabs.candidates.filterNot(selected::contains)
    val full = selected.size >= NavTabs.MAX_CONTENT
    LazyColumn(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item(key = "header-shown") {
            Text(
                stringResource(R.string.settings_navbar_shown, selected.size, NavTabs.MAX_CONTENT),
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        items(selected, key = { "sel:$it" }) { route ->
            NavBarRow(
                route = route,
                checked = true,
                // Letzter angezeigter Tab lässt sich nicht abwählen
                // (leere Leiste wäre unbedienbar).
                checkEnabled = selected.size > 1,
                onCheckedChange = { onSelectionChange(selected - route) },
                onMoveUp = { onSelectionChange(NavTabs.move(selected, selected.indexOf(route), -1)) },
                onMoveDown = { onSelectionChange(NavTabs.move(selected, selected.indexOf(route), 1)) },
                moveUpEnabled = selected.indexOf(route) > 0,
                moveDownEnabled = selected.indexOf(route) < selected.lastIndex,
            )
        }
        if (unselected.isNotEmpty()) {
            item(key = "header-add") {
                Text(
                    stringResource(R.string.settings_navbar_add),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
        items(unselected, key = { "add:$it" }) { route ->
            NavBarRow(
                route = route,
                checked = false,
                checkEnabled = !full,
                onCheckedChange = { onSelectionChange(selected + route) },
                onMoveUp = {},
                onMoveDown = {},
                moveUpEnabled = false,
                moveDownEnabled = false,
                showArrows = false,
            )
        }
        if (full) {
            item(key = "header-max") {
                Text(
                    stringResource(R.string.settings_navbar_max),
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun NavBarRow(
    route: String,
    checked: Boolean,
    checkEnabled: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    moveUpEnabled: Boolean,
    moveDownEnabled: Boolean,
    showArrows: Boolean = true,
) {
    val scheme = MaterialTheme.colorScheme
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = scheme.surfaceVariant,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
        ) {
            Checkbox(
                checked = checked,
                enabled = checkEnabled,
                onCheckedChange = onCheckedChange,
            )
            Icon(
                NavTabs.iconFor(route),
                contentDescription = null,
                tint = scheme.primary,
                modifier = Modifier.size(22.dp),
            )
            Spacer(Modifier.width(12.dp))
            Text(
                NavTabs.label(route),
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = scheme.onSurface,
                modifier = Modifier.weight(1f),
            )
            if (showArrows) {
                IconButton(onClick = onMoveUp, enabled = moveUpEnabled) {
                    Icon(
                        Icons.Filled.KeyboardArrowUp,
                        contentDescription = stringResource(R.string.navbar_move_up),
                        modifier = Modifier.size(24.dp),
                    )
                }
                IconButton(onClick = onMoveDown, enabled = moveDownEnabled) {
                    Icon(
                        Icons.Filled.KeyboardArrowDown,
                        contentDescription = stringResource(R.string.navbar_move_down),
                        modifier = Modifier.size(24.dp),
                    )
                }
            }
        }
    }
}
