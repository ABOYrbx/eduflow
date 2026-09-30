package de.eduflow.android.ui.auth

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.MailOutline
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.R
import de.eduflow.android.data.ApiClient
import de.eduflow.android.data.TokenStore
import de.eduflow.android.data.normalizeBaseUrl
import de.eduflow.android.ui.common.EduCard
import de.eduflow.android.ui.common.PrimaryButton
import de.eduflow.android.ui.common.SearchPill
import de.eduflow.android.ui.theme.EduFlowRiseEasing
import de.eduflow.android.ui.theme.LocalReducedMotion
import de.eduflow.android.ui.theme.riseIn
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.runtime.withFrameNanos
import kotlin.math.floor
import kotlin.math.sin

/** Onboarding: Willkommen → Sprache → Funktionen → Server prüfen → EduPage-Login. */
@Composable
fun OnboardingFlow(
    vm: AuthViewModel,
    baseUrl: String,
    onBaseUrlChange: suspend (String) -> Unit,
    onTwoFa: (String) -> Unit,
) {
    var page by remember { mutableIntStateOf(0) }
    val reducedMotion = LocalReducedMotion.current
    Box(Modifier.fillMaxSize()) {
        AnimatedContent(
            targetState = page,
            transitionSpec = {
                val direction = if (targetState > initialState) 1 else -1
                (if (reducedMotion) EnterTransition.None else
                    slideInHorizontally(tween(250, easing = FastOutSlowInEasing)) { it * direction } + fadeIn(tween(180))) togetherWith
                    (if (reducedMotion) ExitTransition.None else
                        slideOutHorizontally(tween(250, easing = FastOutSlowInEasing)) { -it * direction } + fadeOut(tween(180)))
            },
            label = "onboarding-page",
        ) { current ->
            when (current) {
                0 -> WelcomePage(onNext = { page = 1 })
                1 -> LanguagePage(onNext = { page = 2 })
                2 -> FeaturesPage(onNext = { page = 3 })
                3 -> ServerPage(baseUrl = baseUrl, onApply = { url -> onBaseUrlChange(url); page = 4 })
                else -> LoginScreen(
                    vm = vm,
                    baseUrl = baseUrl,
                    onBaseUrlChange = onBaseUrlChange,
                    onTwoFa = onTwoFa,
                    showServerStep = false,
                )
            }
        }
        // Durchgehende Partikel-Ebene über die komplette Displayfläche und
        // alle Schritte hinweg; Canvas nimmt keine Touch-Eingaben entgegen.
        if (!reducedMotion) {
            SparkleField(Modifier.fillMaxSize().graphicsLayer { alpha = 0.48f })
        }
    }
}

/** Entspricht dem Mac-Einstieg: Buchstaben-Gruß, schwebendes Logo, Funken und verzögerter CTA. */
@Composable
private fun WelcomePage(onNext: () -> Unit) {
    val reducedMotion = LocalReducedMotion.current
    val density = LocalDensity.current
    val context = androidx.compose.ui.platform.LocalContext.current
    val greetings = remember {
        AppLocale.greetingEntries(AppLocale.availableLocales(context)) {
            AppLocale.greetingFor(it, context)
        }
    }
    // Sprache der aktuell gezeigten Begrüßung — der Weiter-Knopf spricht sie.
    var buttonLocale by remember { mutableStateOf("") }
    var showButton by remember { mutableStateOf(reducedMotion) }
    LaunchedEffect(reducedMotion) {
        if (reducedMotion) showButton = true else {
            delay(3_000)
            showButton = true
        }
    }
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 28.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        HelloGreeting(greetings) { buttonLocale = it }
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.fillMaxWidth().height(280.dp).padding(top = 8.dp).riseIn(index = 10),
        ) {
            Image(
                painter = painterResource(R.drawable.logo),
                contentDescription = stringResource(R.string.app_name),
                contentScale = androidx.compose.ui.layout.ContentScale.Fit,
                modifier = Modifier.size(96.dp)
                    .clip(RoundedCornerShape(22.dp))
                    .shadow(16.dp, RoundedCornerShape(22.dp)),
            )
        }
        Spacer(Modifier.weight(1f))
        androidx.compose.animation.AnimatedVisibility(
            visible = showButton,
            enter = if (reducedMotion) fadeIn(tween(1)) else
                fadeIn(tween(550, easing = EduFlowRiseEasing)) +
                    androidx.compose.animation.slideInVertically(tween(550, easing = EduFlowRiseEasing)) { with(density) { 22.dp.roundToPx() } } +
                    androidx.compose.animation.scaleIn(spring(dampingRatio = 0.55f, stiffness = 260f), initialScale = 0.985f),
            modifier = Modifier.fillMaxWidth(),
        ) {
            AnimatedNextButton(
                text = AppLocale.stringFor(buttonLocale, R.string.common_next, context),
                onClick = onNext,
            )
        }
    }
}

/**
 * Weiter-Knopf der Startseite, dessen Text beim Sprachwechsel mitläuft.
 *
 * Optisch identisch zu [PrimaryButton] (Paket 0 bleibt unberührt), aber der
 * Text rollt von unten nach oben, genau wie die Buchstaben der Begrüßung:
 * der neue Satz steigt ein, während der alte nach oben austritt. Bei
 * "Bewegung reduzieren" wird ohne Animation getauscht.
 */
@Composable
private fun AnimatedNextButton(text: String, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val reduced = LocalReducedMotion.current
    Button(
        onClick = onClick,
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = scheme.primary,
            contentColor = scheme.onPrimary,
        ),
        modifier = Modifier.fillMaxWidth().height(52.dp),
    ) {
        AnimatedContent(
            targetState = text,
            transitionSpec = {
                if (reduced) EnterTransition.None togetherWith ExitTransition.None
                else (
                    slideInVertically(tween(380, easing = EduFlowRiseEasing)) { it / 2 } +
                        fadeIn(tween(380, easing = EduFlowRiseEasing)) +
                        scaleIn(tween(380, easing = EduFlowRiseEasing), initialScale = 0.92f)
                    ) togetherWith (
                    slideOutVertically(tween(240, easing = FastOutSlowInEasing)) { -it / 2 } +
                        fadeOut(tween(240, easing = FastOutSlowInEasing)) +
                        scaleOut(tween(240, easing = FastOutSlowInEasing), targetScale = 0.92f)
                    )
            },
            contentAlignment = Alignment.Center,
            label = "next-label",
        ) { value ->
            Text(value, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

/** Sprachauswahl als zweite Onboarding-Seite: Suchfeld + Liste mit Stand; Auswahl wirkt sofort. */
@Composable
private fun LanguagePage(onNext: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val context = LocalContext.current
    // Auswahl live beobachten, damit der Stand nach dem Setzen stimmt.
    val current by AppLocale.selectionFlow(context).collectAsState(initial = null)
    val available = remember { AppLocale.availableLocales(context) }
    val system = remember(available) { AppLocale.systemCode(available) }
    // Ohne eigene Wahl gilt die Systemsprache — sie ist einfach markiert,
    // ein eigener „System"-Eintrag wäre doppelt.
    var selected by remember(current, system) { mutableStateOf(AppLocale.initialSelection(current, system)) }
    var query by remember { mutableStateOf("") }
    val codes = remember(query, available, system) {
        AppLocale.filterLanguages(AppLocale.orderedLanguages(available, system), query)
    }
    // Die vorausgewählte Systemsprache wird nicht festgenagelt: erst wenn die
    // Nutzerin tatsächlich eine Sprache antippt, wird sie gespeichert.

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 28.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            stringResource(R.string.onboarding_language_title),
            fontSize = 30.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = (-1.2).sp,
            textAlign = TextAlign.Center,
            color = scheme.onBackground,
            modifier = Modifier.padding(top = 12.dp).riseIn(index = 2),
        )
        Text(
            stringResource(R.string.onboarding_language_sub),
            fontSize = 14.sp,
            lineHeight = 20.sp,
            textAlign = TextAlign.Center,
            color = scheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 10.dp, start = 24.dp, end = 24.dp).riseIn(index = 3),
        )
        if (system != null) {
            Text(
                stringResource(R.string.onboarding_language_system_format, AppLocale.nativeName(system)),
                fontSize = 13.sp,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 8.dp).riseIn(index = 5),
            )
        }
        SearchPill(
            value = query,
            onValueChange = { query = it },
            placeholder = stringResource(R.string.onboarding_language_search),
            modifier = Modifier.padding(top = 16.dp).riseIn(index = 4),
        )
        // Listenhöhe über weight begrenzt, damit der Weiter-Knopf nie
        // überlagert wird; zusätzlich Luft nach unten, damit die letzte
        // Zeile beim Scrollen nicht unter dem Knopf verschwindet.
        Column(
            modifier = Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState())
                .padding(top = 12.dp, bottom = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (codes.isEmpty()) {
                Text(
                    stringResource(R.string.onboarding_language_no_results),
                    fontSize = 14.sp,
                    color = scheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp),
                    textAlign = TextAlign.Center,
                )
            }
            codes.forEach { code ->
                val isSelected = selected == code
                EduCard(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        // Wirkt sofort: die Umschaltung ist live, ein
                        // separater "Übernehmen"-Schritt wäre überflüssig —
                        // der Knopf bleibt daher immer "Weiter".
                        modifier = Modifier.fillMaxWidth().padding(16.dp).clickable {
                            selected = code
                            AppLocale.set(context, code)
                        },
                    ) {
                        Box(
                            contentAlignment = Alignment.Center,
                            modifier = Modifier.size(22.dp)
                                .border(2.dp, scheme.outline, CircleShape)
                                .padding(5.dp)
                                .clip(CircleShape)
                                .background(if (isSelected) scheme.primary else Color.Transparent),
                        ) {}
                        Column(Modifier.padding(start = 14.dp).weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    AppLocale.nativeName(code),
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Black,
                                    letterSpacing = (-0.2).sp,
                                    color = scheme.onSurface,
                                    modifier = Modifier.weight(1f),
                                )
                                if (code == system && current == null) {
                                    // Kennzeichnet, was ohne eigene Wahl gilt.
                                    Text(
                                        stringResource(R.string.onboarding_language_system_short),
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = scheme.onSurfaceVariant,
                                        modifier = Modifier
                                            .padding(end = 8.dp)
                                            .clip(CircleShape)
                                            .background(scheme.surfaceVariant)
                                            .padding(horizontal = 8.dp, vertical = 2.dp),
                                    )
                                }
                                Text(
                                    "${AppLocale.coverageFor(code).percent} %",
                                    fontSize = 13.sp,
                                    color = scheme.onSurfaceVariant,
                                )
                            }
                            LinearProgressIndicator(
                                progress = { AppLocale.coverageFor(code).percent / 100f },
                                modifier = Modifier.fillMaxWidth().height(4.dp).clip(CircleShape),
                            )
                        }
                    }
                }
            }
        }
        PrimaryButton(
            // Die Sprache ist beim Tippen bereits gesetzt — der Knopf ist nur
            // noch "Weiter" zur naechsten Onboarding-Seite.
            text = stringResource(R.string.common_next),
            enabled = selected != null,
            onClick = onNext,
            modifier = Modifier.riseIn(index = 7),
        )
    }
}

@Composable
private fun HelloGreeting(
    entries: List<Pair<String, String>> = emptyList(),
    onLanguage: (String) -> Unit = {},
) {
    val reduced = LocalReducedMotion.current
    val fallback = stringResource(R.string.onboarding_greeting)
    val list = remember(entries) {
        if (entries.isEmpty()) listOf("" to fallback) else entries
    }
    var order by remember(list) { mutableStateOf(AppLocale.shuffledCycle(list.size, null)) }
    var position by remember(list) { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val shown = list[order[position % order.size]]
    // Sprache der gerade gezeigten Begrüßung melden, damit der Weiter-Knopf
    // auf derselben Seite mitwechselt. Leer = App-Sprache (Fallback).
    LaunchedEffect(shown.first) { onLanguage(shown.first) }
    key(order, position) {
        GreetingText(text = shown.second) {
            scope.launch {
                delay(2_000)
                val next = position + 1
                if (next >= order.size) {
                    order = AppLocale.shuffledCycle(list.size, order.lastOrNull())
                    position = 0
                } else {
                    position = next
                }
            }
        }
    }
}

@Composable
private fun GreetingText(text: String, onDone: () -> Unit) {
    val reduced = LocalReducedMotion.current
    val scheme = MaterialTheme.colorScheme
    var waveVisible by remember { mutableStateOf(reduced) }
    LaunchedEffect(text) {
        if (!reduced) delay(text.length * 70L + 100L)
        onDone()
    }
    LaunchedEffect(reduced, text) {
        if (reduced) waveVisible = true else {
            delay(text.length * 70L)
            waveVisible = true
        }
    }
    val wave = if (reduced) 0f else {
        val transition = rememberInfiniteTransition(label = "wave")
        val angle by transition.animateFloat(
            initialValue = -12f,
            targetValue = 18f,
            animationSpec = infiniteRepeatable(tween(500), repeatMode = RepeatMode.Reverse),
            label = "wave-angle",
        )
        angle
    }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
        text.forEachIndexed { index, char ->
            var visible by remember { mutableStateOf(reduced) }
            LaunchedEffect(reduced) {
                if (reduced) visible = true else {
                    delay(index * 70L)
                    visible = true
                }
            }
            val alpha by androidx.compose.animation.core.animateFloatAsState(
                targetValue = if (visible) 1f else 0f,
                animationSpec = spring(dampingRatio = 0.55f, stiffness = 250f),
                label = "greeting-$index",
            )
            Text(
                char.toString(),
                fontSize = 44.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = (-1.5).sp,
                color = scheme.onBackground,
                modifier = Modifier.graphicsLayer {
                    this.alpha = alpha
                    translationY = if (visible) 0f else 22.dp.toPx()
                    scaleX = if (visible) 1f else 0.85f
                    scaleY = if (visible) 1f else 0.85f
                },
            )
        }
        Text(
            "👋",
            fontSize = 34.sp,
            modifier = Modifier.padding(start = 12.dp).graphicsLayer {
                alpha = if (waveVisible) 1f else 0f
                rotationZ = if (waveVisible) wave else -12f
            },
        )
    }
}

@Composable
private fun SparkleField(modifier: Modifier = Modifier) {
    val dark = androidx.compose.foundation.isSystemInDarkTheme()
    var elapsedSeconds by remember { mutableDoubleStateOf(0.0) }
    LaunchedEffect(Unit) {
        var previousFrame = 0L
        while (true) {
            withFrameNanos { now ->
                if (previousFrame != 0L) {
                    elapsedSeconds += (now - previousFrame) / 1_000_000_000.0
                }
                previousFrame = now
            }
        }
    }
    Canvas(modifier) {
        repeat(72) { i ->
            // Jeder Punkt bekommt eine fortlaufende Folge pseudozufälliger
            // Wegpunkte. Benachbarte Segmente teilen sich ihren Endpunkt;
            // dadurch gibt es keinen Reset oder Sprung zum Anfang.
            val travel = elapsedSeconds / (5.5 + (i % 7) * 0.8)
            val segment = floor(travel).toLong()
            val linear = (travel - segment).toFloat()
            val progress = linear * linear * (3f - 2f * linear)
            val from = sparklePoint(i, segment)
            val to = sparklePoint(i, segment + 1)
            val x = size.width * (from.first + (to.first - from.first) * progress)
            val y = size.height * (from.second + (to.second - from.second) * progress)
            val alpha = 0.34f + sparkleRandom(i.toLong() * 97L + 11L) * 0.44f
            // Weiße Punkte im Dark Mode; hellgrau im Light Mode für Kontrast.
            val particle = if (dark) Color.White else Color(0xFFB8B8B8)
            drawCircle(particle.copy(alpha = alpha), radius = (1.2f + (i % 4) * 0.65f).dp.toPx(), center = androidx.compose.ui.geometry.Offset(x, y))
        }
    }
}

private fun sparklePoint(particle: Int, waypoint: Long): Pair<Float, Float> {
    val seed = particle.toLong() * 1_000_003L + waypoint * 97_409L
    return sparkleRandom(seed) to sparkleRandom(seed + 47_111L)
}

private fun sparkleRandom(seed: Long): Float {
    var value = seed + 0x9E3779B97F4A7C15UL.toLong()
    value = (value xor (value ushr 30)) * 0xBF58476D1CE4E5B9UL.toLong()
    value = (value xor (value ushr 27)) * 0x94D049BB133111EBUL.toLong()
    value = value xor (value ushr 31)
    return ((value ushr 40) and 0xFFFFFF).toFloat() / 0xFFFFFF
}

/** Drei Feature-Karten mit derselben Reihenfolge und derselben Staffelung wie auf dem Mac. */
@Composable
private fun FeaturesPage(onNext: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Box(Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier.fillMaxSize().padding(horizontal = 28.dp, vertical = 24.dp),
        ) {
            Spacer(Modifier.weight(1f))
            Text(
                stringResource(R.string.onboarding_features_title),
                fontSize = 30.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = (-1.2).sp,
                color = scheme.onBackground,
                modifier = Modifier.padding(top = 12.dp).riseIn(index = 2),
            )
            Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(top = 22.dp)) {
                // Icons wie in der Navigation zum jeweiligen Bereich.
                FeatureRow(Icons.Filled.MailOutline, stringResource(R.string.onboarding_feat1_title), stringResource(R.string.onboarding_feat1_desc), 3)
                FeatureRow(Icons.Filled.Checklist, stringResource(R.string.onboarding_feat2_title), stringResource(R.string.onboarding_feat2_desc), 4)
                FeatureRow(Icons.Filled.CalendarMonth, stringResource(R.string.onboarding_feat3_title), stringResource(R.string.onboarding_feat3_desc), 6)
            }
            Spacer(Modifier.weight(1f))
            PrimaryButton(text = stringResource(R.string.common_next), onClick = onNext, modifier = Modifier.riseIn(index = 7))
        }
    }
}

/**
 * Karte einer Faehigkeit mit Icon-Kreis. Das Icon kommt aus
 * material-icons-extended und ist dasselbe wie in der Navigation zum
 * passenden Bereich — vorher standen hier hartcodierte Unicode-Glyphen
 * ("✉", "☷", "▦"), die wie fremde Textzeichen aussahen statt wie Icons.
 */
@Composable
private fun FeatureRow(icon: ImageVector, title: String, description: String, delayIndex: Int) {
    val scheme = MaterialTheme.colorScheme
    EduCard(modifier = Modifier.fillMaxWidth().riseIn(index = delayIndex)) {
        Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Surface(shape = CircleShape, color = scheme.primary, modifier = Modifier.size(40.dp)) {
                Box(contentAlignment = Alignment.Center) {
                    // Dekorativ: der Titel steht direkt daneben, eine
                    // contentDescription wuerde nur doppelt vorlesen.
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = scheme.onPrimary,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
            Column(Modifier.padding(start = 14.dp).weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(title, fontSize = 15.sp, fontWeight = FontWeight.Black, letterSpacing = (-0.2).sp, color = scheme.onSurface)
                Text(description, fontSize = 13.sp, lineHeight = 18.sp, color = scheme.onSurfaceVariant)
            }
        }
    }
}

/** Mac-Serverseite: Test separat, Übernehmen testet erneut und übernimmt erst bei Erfolg. */
@Composable
private fun ServerPage(baseUrl: String, onApply: suspend (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val reducedMotion = LocalReducedMotion.current
    // baseUrl ist der interne Notfallwert, wenn nichts gespeichert ist —
// dann soll das Feld trotzdem leer sein (keine Voreinstellung). Nur eine
// wirklich gespeicherte Adresse wird vorbelegt.
    val storedBaseUrl = baseUrl.takeIf { it.isNotBlank() && it != TokenStore.DEFAULT_BASE_URL }
    var draft by remember(storedBaseUrl) { mutableStateOf(storedBaseUrl.orEmpty()) }
    var checking by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var connected by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val connectedText = stringResource(R.string.onboarding_connected)
    val unreachableText = stringResource(R.string.onboarding_unreachable)

    // Ohne Eingabe gibt es nichts zu testen: leer heisst "kein Server
    // eingetragen", nicht "nimm den Emulator-Host".
    val canTest = draft.isNotBlank()
    fun normalizedUrl(): String = normalizeBaseUrl(draft)

    suspend fun checkConnection() {
        if (!canTest) return
        checking = true
        message = null
        connected = false
        val normalized = normalizedUrl()
        val result = runCatching { ApiClient.create(normalized) { null }.health() }
        checking = false
        if (result.isSuccess && result.getOrNull()?.isSuccessful == true) {
            draft = normalized
            connected = true
            message = connectedText
        } else {
            message = unreachableText
        }
    }

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 28.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
      Spacer(Modifier.weight(1f))
      Column(
          modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()),
          horizontalAlignment = Alignment.CenterHorizontally,
      ) {
        Text(
            stringResource(R.string.auth_hint_server),
            fontSize = 30.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = (-1.2).sp,
            textAlign = TextAlign.Center,
            color = scheme.onBackground,
            modifier = Modifier.padding(top = 12.dp).riseIn(index = 2),
        )
        Text(
            stringResource(R.string.onboarding_server_sub),
            fontSize = 14.sp,
            lineHeight = 20.sp,
            textAlign = TextAlign.Center,
            color = scheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 10.dp, start = 24.dp, end = 24.dp).riseIn(index = 3),
        )
        OutlinedTextField(
            value = draft,
            onValueChange = { draft = it; message = null; connected = false },
            // Nur IP genügt, Port ist optional — der Hinweis sagt beides.
            placeholder = { Text(TokenStore.SERVER_PLACEHOLDER) },
            supportingText = if (draft.isBlank()) {
                {
                    Text(
                        stringResource(
                            R.string.onboarding_server_hint,
                            TokenStore.DEFAULT_PORT,
                            TokenStore.DEMO_PORT,
                        ),
                        fontSize = 12.sp,
                    )
                }
            } else {
                null
            },
            leadingIcon = { Icon(Icons.Filled.Dns, contentDescription = null) },
            singleLine = true,
            shape = CircleShape,
            modifier = Modifier.fillMaxWidth().padding(top = 20.dp).riseIn(index = 4),
        )
        Spacer(Modifier.height(16.dp))
      }
      Spacer(Modifier.weight(1f))
      Spacer(Modifier.height(12.dp))
      Button(
          onClick = { scope.launch { checkConnection() } },
          enabled = !checking && canTest,
          shape = CircleShape,
          colors = ButtonDefaults.buttonColors(
              containerColor = when {
                  connected -> Color(0xFF16A34A)
                  message != null -> scheme.error
                  else -> scheme.onBackground
              },
              contentColor = if (connected || message != null) Color.White else scheme.background,
          ),
          modifier = Modifier.fillMaxWidth().height(44.dp).riseIn(index = 5),
      ) {
          if (checking) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
          else Text(
              when {
                  connected -> stringResource(R.string.onboarding_test_connected)
                  message != null -> stringResource(R.string.onboarding_test_failed)
                  else -> stringResource(R.string.onboarding_test_action)
              },
              fontWeight = FontWeight.SemiBold,
          )
      }
      message?.takeUnless { connected }?.let {
          Text(it, color = scheme.error, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 6.dp))
      }
      Spacer(Modifier.height(10.dp))
        PrimaryButton(
            text = stringResource(R.string.common_next),
            onClick = { scope.launch { onApply(normalizedUrl().trimEnd('/')) } },
            enabled = connected && !checking,
            modifier = Modifier.riseIn(index = 7),
        )
    }
}
