package de.eduflow.android.ui.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.stringResource
import de.eduflow.android.R
import de.eduflow.android.ui.common.PrimaryButton
import de.eduflow.android.ui.common.SectionLabel
import de.eduflow.android.ui.timetable.localizedApiMessage

// 2FA-Screen aus dem Redesign-PNG (Paket A, Screen 06, „2 VON 2"):
/// Code-Feld + „Bestätigen", zurück zum Login. Logik unverändert.
@Composable
fun TwoFaScreen(
    vm: AuthViewModel,
    pendingToken: String,
    onLoggedIn: () -> Unit,
    onBackToLogin: () -> Unit,
) {
    var code by remember { mutableStateOf("") }
    val state by vm.twoFa.collectAsState()
    val loading = state is TwoFaUiState.Loading
    val scheme = MaterialTheme.colorScheme

    Column(
        modifier = Modifier.fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        SectionLabel(stringResource(R.string.twofa_section))
        Text(
            stringResource(R.string.twofa_title),
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = scheme.onBackground,
        )
        Text(
            stringResource(R.string.twofa_desc),
            style = MaterialTheme.typography.bodyMedium,
            color = scheme.onSurfaceVariant,
        )
        Text(
            stringResource(R.string.twofa_label),
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = scheme.onSurface,
        )
        OutlinedTextField(
            value = code,
            onValueChange = { code = it },
            placeholder = { Text(stringResource(R.string.twofa_placeholder)) },
            singleLine = true,
            shape = CircleShape,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            textStyle = MaterialTheme.typography.bodyMedium,
            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = scheme.surface,
                unfocusedContainerColor = scheme.surface,
                unfocusedBorderColor = scheme.outlineVariant,
                focusedBorderColor = scheme.primary,
                cursorColor = scheme.primary,
            ),
            modifier = Modifier.fillMaxWidth(),
        )
        if (state is TwoFaUiState.Error) {
            val err = state as TwoFaUiState.Error
            Text(
                localizedApiMessage(err.code, err.message, err.messageRes),
                color = scheme.error,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        if (loading) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
            ) {
                CircularProgressIndicator()
            }
        }
        PrimaryButton(
            text = if (loading) stringResource(R.string.twofa_confirm_loading) else stringResource(R.string.twofa_confirm),
            onClick = { vm.submit2fa(pendingToken, code, onLoggedIn) },
            enabled = !loading,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = onBackToLogin) {
                Text(stringResource(R.string.twofa_back))
            }
        }
        Text(
            stringResource(R.string.twofa_validity),
            fontSize = 12.sp,
            color = scheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}
