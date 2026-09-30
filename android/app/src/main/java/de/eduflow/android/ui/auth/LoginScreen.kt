package de.eduflow.android.ui.auth

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.R
import de.eduflow.android.data.defaultDeviceName
import de.eduflow.android.data.normalizeBaseUrl
import de.eduflow.android.data.TokenStore
import de.eduflow.android.ui.common.PrimaryButton
import de.eduflow.android.ui.timetable.localizedApiMessage
import de.eduflow.android.ui.theme.LocalReducedMotion
import kotlinx.coroutines.launch

/** Vierstufige Anmeldung wie auf dem Mac: Benutzername, Passwort, Gerät, Server. */
@Composable
fun LoginScreen(
    vm: AuthViewModel,
    baseUrl: String,
    onBaseUrlChange: suspend (String) -> Unit,
    onTwoFa: (pending: String) -> Unit,
    showServerStep: Boolean = true,
) {
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    // Vorbelegung lokalisiert (Gerätename landet in der Geräte-Liste);
    // leeres Feld fällt beim Anmelden erneut auf diesen String zurück.
    val emulatorLabel = stringResource(R.string.device_default_name)
    var device by remember(emulatorLabel) { mutableStateOf(defaultDeviceName(emulatorLabel)) }
    var server by remember(baseUrl) { mutableStateOf(baseUrl) }
    var step by remember { mutableIntStateOf(0) }
    var showServerConfirm by remember { mutableStateOf(false) }
    val state by vm.login.collectAsState()
    val reducedMotion = LocalReducedMotion.current
    val scope = rememberCoroutineScope()
    val scheme = MaterialTheme.colorScheme

    LaunchedEffect(state) {
        when (val result = state) {
            is LoginUiState.TwoFa -> {
                onTwoFa(result.pendingToken)
                vm.consumeTwoFaState()
            }
            else -> Unit
        }
    }

    val loading = state is LoginUiState.Loading
    val loginError = state as? LoginUiState.Error
    val stepCount = if (showServerStep) 4 else 3
    val lastStep = stepCount - 1

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 32.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            modifier = Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(12.dp))
            Image(
                painter = painterResource(R.drawable.logo),
                contentDescription = stringResource(R.string.app_name),
                contentScale = ContentScale.Fit,
                modifier = Modifier.size(96.dp).clip(androidx.compose.foundation.shape.RoundedCornerShape(22.dp))
                    .shadow(12.dp, androidx.compose.foundation.shape.RoundedCornerShape(22.dp)),
            )
            Text(stringResource(R.string.app_name), fontSize = 28.sp, fontWeight = FontWeight.Black, letterSpacing = (-0.8).sp, color = scheme.onBackground, modifier = Modifier.padding(top = 20.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 14.dp)) {
                repeat(stepCount) { index ->
                    val dotWidth by animateDpAsState(
                        targetValue = if (index == step) 24.dp else 8.dp,
                        animationSpec = tween(if (reducedMotion) 1 else 200),
                        label = "login-step-$index",
                    )
                    Surface(
                        shape = CircleShape,
                        color = if (index <= step) scheme.primary else scheme.outlineVariant,
                        modifier = Modifier.size(width = dotWidth, height = 8.dp),
                    ) {}
                }
            }
            Text(stringResource(R.string.auth_step_format, step + 1, stepCount), fontSize = 12.sp, color = scheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp, bottom = 16.dp))
            loginError?.let {
                Text(
                    localizedApiMessage(it.code, it.message, it.messageRes),
                    color = scheme.error,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(bottom = 10.dp),
                )
            }

            AnimatedContent(
                targetState = step,
                transitionSpec = {
                    val direction = if (targetState > initialState) 1 else -1
                    (if (reducedMotion) EnterTransition.None else
                        slideInHorizontally(tween(250, easing = FastOutSlowInEasing)) { it * direction } + fadeIn(tween(180))) togetherWith
                        (if (reducedMotion) ExitTransition.None else
                            slideOutHorizontally(tween(250, easing = FastOutSlowInEasing)) { -it * direction } + fadeOut(tween(180)))
                },
                label = "login-step",
            ) { page ->
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                    when (page) {
                        0 -> {
                            StepHint(stringResource(R.string.auth_hint_username))
                            LoginField(stringResource(R.string.auth_label_username), username, { username = it; vm.consumeLoginError() }, stringResource(R.string.auth_placeholder_username), KeyboardType.Text)
                        }
                        1 -> {
                            StepHint(stringResource(R.string.auth_hint_password))
                            LoginField(stringResource(R.string.auth_label_password), password, { password = it; vm.consumeLoginError() }, stringResource(R.string.auth_placeholder_password), KeyboardType.Password, password = true)
                        }
                        2 -> {
                            StepHint(stringResource(R.string.auth_hint_device))
                            LoginField(stringResource(R.string.auth_label_device), device, { device = it }, stringResource(R.string.auth_placeholder_device), KeyboardType.Text)
                        }
                        else -> {
                            StepHint(stringResource(R.string.auth_hint_server))
                            // Leer starten, kein Vorschlag: der Hinweis ist nur
                            // der Placeholder, die Eingabe ist die IP des Servers.
                            LoginField(stringResource(R.string.auth_label_server), server, { server = it; showServerConfirm = false }, TokenStore.SERVER_PLACEHOLDER, KeyboardType.Uri)
                            TextButton(
                                enabled = server.isNotBlank(),
                                onClick = {
                                    scope.launch {
                                        onBaseUrlChange(server.trim().trimEnd('/'))
                                        showServerConfirm = true
                                    }
                                },
                            ) {
                                Text(if (showServerConfirm) stringResource(R.string.common_applied) else stringResource(R.string.common_apply))
                            }
                            // Nur den tatsaechlichen Stand zeigen, nicht die
                            // fertige URL erfinden, wenn nichts eingetragen ist.
                            if (server.isNotBlank()) {
                                Text(
                                    stringResource(R.string.auth_server_current_format, normalizeBaseUrl(server)),
                                    fontSize = 12.sp,
                                    color = scheme.onSurfaceVariant,
                                    textAlign = TextAlign.Center,
                                )
                            }
                        }
                    }
                }
            }

            if (loading) {
                CircularProgressIndicator(modifier = Modifier.padding(top = 12.dp))
            }
            if (step == lastStep) {
                Text(
                    stringResource(R.string.auth_privacy_note),
                    fontSize = 12.sp,
                    color = scheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 18.dp, bottom = 16.dp),
                )
            }
            Spacer(Modifier.height(16.dp))
        }

        if (step < lastStep) {
            if (step > 0) {
                TextButton(
                    onClick = { step = (step - 1).coerceAtLeast(0); vm.consumeLoginError() },
                    modifier = Modifier.align(Alignment.Start),
                ) {
                    Text(stringResource(R.string.common_back), fontWeight = FontWeight.Bold, color = scheme.onSurfaceVariant)
                }
            }
            PrimaryButton(
                text = stringResource(R.string.common_next),
                    onClick = { step += 1; vm.consumeLoginError() },
                    enabled = canAdvance(step, username, password),
            )
        } else {
            if (step > 0) {
                TextButton(
                    onClick = { step = (step - 1).coerceAtLeast(0); vm.consumeLoginError() },
                    modifier = Modifier.align(Alignment.Start),
                ) { Text(stringResource(R.string.common_back), fontWeight = FontWeight.Bold, color = scheme.onSurfaceVariant) }
            }
            PrimaryButton(
                text = if (loading) stringResource(R.string.auth_login_loading) else stringResource(R.string.auth_login),
                onClick = {
                    scope.launch {
                        // Nur uebernehmen wenn etwas drinsteht; sonst bleibt
                        // der gespeicherte Server unangetastet (der Schritt
                        // laesst sich auch ohne Eingabe bestaetigen).
                        if (showServerStep && server.isNotBlank()) {
                            onBaseUrlChange(server.trim())
                        }
                        vm.login(username, password, device.ifBlank { emulatorLabel })
                    }
                },
                enabled = !loading,
            )
        }
    }
}

private fun canAdvance(step: Int, username: String, password: String): Boolean = when (step) {
    0 -> username.isNotBlank()
    1 -> password.isNotEmpty()
    else -> true
}

@Composable
private fun StepHint(text: String) {
    Text(
        text,
        fontSize = 14.sp,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
    )
}

@Composable
private fun LoginField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    keyboardType: KeyboardType,
    password: Boolean = false,
) {
    val scheme = MaterialTheme.colorScheme
    Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.fillMaxWidth()) {
        Text(label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = scheme.onSurface)
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = { Text(placeholder) },
            singleLine = true,
            shape = CircleShape,
            visualTransformation = if (password) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
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
    }
}
