"""Jinja runtime translation and Babel extraction for static HTML markup.

Only literal template text and literal, user-facing accessibility attributes
are translated. Jinja expressions, school content, provider messages, scripts,
and styles remain data/code and are never sent to gettext.
"""

from __future__ import annotations

import gettext as gettext_module
import html
import re
from functools import lru_cache
from pathlib import Path
from typing import Callable, Optional, Tuple

from jinja2 import Environment
from jinja2.ext import Extension, babel_extract
from jinja2.lexer import Token
from markupsafe import Markup

_TRANSLATABLE_ATTRIBUTES = frozenset(("alt", "aria-label", "placeholder", "title"))
_RAW_ELEMENTS = frozenset(("script", "style"))
_TAG_START = re.compile(r"</?([A-Za-z][A-Za-z0-9:_-]*)")
_ATTRIBUTE = re.compile(
    r"(?P<prefix>\s+)(?P<name>[A-Za-z_:][A-Za-z0-9:_.-]*)"
    r"(?P<between>\s*=\s*)(?P<quote>['\"])(?P<value>.*?)(?P=quote)"
)


def normalize_locale(value: str) -> str:
    """Normalize common Crowdin/HTTP locale spellings to Babel identifiers."""
    parts = (value or "").strip().replace("-", "_").split("_")
    if not parts or not parts[0]:
        return ""
    return "_".join([parts[0].lower(), *(part.upper() for part in parts[1:])])


def available_locales(translation_root: Path) -> Tuple[str, ...]:
    """Return German plus locales with at least one non-empty compiled entry."""
    locales = {"de"}
    try:
        catalogs = translation_root.glob("*/LC_MESSAGES/messages.mo")
    except OSError:
        return tuple(sorted(locales))

    for catalog_path in catalogs:
        locale = normalize_locale(catalog_path.parents[1].name)
        if not locale or locale == "templates":
            continue
        try:
            with catalog_path.open("rb") as catalog_file:
                catalog = gettext_module.GNUTranslations(catalog_file)
            if any(
                isinstance(item, str) and item and item != key
                for key, value in getattr(catalog, "_catalog", {}).items()
                if isinstance(key, str) and key
                for item in (value if isinstance(value, tuple) else (value,))
            ):
                locales.add(locale)
        except (OSError, EOFError, ValueError):
            continue
    return tuple(sorted(locales))


def locale_name(locale: str) -> str:
    """Human-readable names for supported source/target locale codes."""
    return {"de": "Deutsch", "en": "English"}.get(locale, locale)


def select_locale(cookie_locale: str, accept_languages, enabled_locales) -> str:
    """Choose only an available catalog, preferring the explicit cookie."""
    enabled = set(enabled_locales)
    saved = normalize_locale(cookie_locale)
    if saved in enabled:
        return saved
    for language, _quality in accept_languages:
        candidate = normalize_locale(language)
        if candidate in enabled:
            return candidate
        base = candidate.split("_", 1)[0]
        if base in enabled:
            return base
    return "de"


@lru_cache(maxsize=32)
def _load_translation(locale: str, modified_ns: int, size: int):
    del modified_ns, size
    if locale == "de":
        return gettext_module.NullTranslations()
    catalog_path = (
        Path(__file__).resolve().parent / "locales" / locale
        / "LC_MESSAGES" / "messages.mo"
    )
    try:
        with catalog_path.open("rb") as catalog_file:
            return gettext_module.GNUTranslations(catalog_file)
    except (OSError, EOFError, ValueError):
        return gettext_module.NullTranslations()


def current_translation():
    """Return the request-selected compiled catalog without compiling PO files."""
    try:
        from flask import g
        locale = getattr(g, "locale", "de")
    except RuntimeError:
        locale = "de"
    if locale == "de":
        return gettext_module.NullTranslations()
    catalog_path = (
        Path(__file__).resolve().parent / "locales" / locale
        / "LC_MESSAGES" / "messages.mo"
    )
    try:
        stat = catalog_path.stat()
        return _load_translation(locale, stat.st_mtime_ns, stat.st_size)
    except OSError:
        return gettext_module.NullTranslations()


def gettext(message: str) -> str:
    """Translate one UI msgid using the current request catalog."""
    return str(current_translation().gettext(message))


def ngettext(singular: str, plural: str, number: int) -> str:
    """Translate a UI plural using the current request catalog."""
    return str(current_translation().ngettext(singular, plural, number))


def get_locale() -> str:
    try:
        from flask import g
        return getattr(g, "locale", "de")
    except RuntimeError:
        return "de"


def translate_static(message: str) -> str:
    """Translate a source-language UI label via the request catalog."""
    return gettext(message)


def localize_api_error(message: str) -> str:
    """Translate cataloged API UI messages but never translate dynamic details."""
    prefixes = (
        "Anmeldung fehlgeschlagen:",
        "2FA fehlgeschlagen:",
        "Download fehlgeschlagen:",
        "Hausaufgaben konnten nicht geladen werden:",
        "Noten konnten nicht geladen werden:",
        "Nachrichten konnten nicht geladen werden:",
        "Thread konnte nicht geladen werden:",
        "Antwort fehlgeschlagen:",
        "Senden fehlgeschlagen:",
        "Empfänger konnten nicht geladen werden:",
        "Einstellungen konnten nicht gespeichert werden:",
        "Cache konnte nicht gelöscht werden:",
        "Stundenplan konnte nicht geladen werden:",
        "Geräte konnten nicht geladen werden:",
        "Essenplan konnte nicht geladen werden:",
        "Status konnte nicht geändert werden:",
        "Aufgabe konnte nicht als offen markiert werden:",
        "Konnte Status nicht ändern:",
        "Konnte Aufgabe nicht wiederherstellen:",
        "Konnte Aufgabe nicht als offen markieren:",
        "Gelesen-Status konnte nicht gespeichert werden:",
        "Antwort wurde gesendet, der Thread konnte aber nicht geladen werden:",
        "Anmeldung erfordert Zwei-Faktor-Code.",
        "Unbekannter Nachrichtentyp.",
        "EduPage meldet Fehler",
        "Nachricht gesendet",
        "Lokaler Cache gelöscht",
        "Token konnte nicht erstellt werden:",
    )
    for prefix in prefixes:
        if message.startswith(prefix):
            return translate_static(prefix) + message[len(prefix):]

    # This allowlist only contains fixed presentation strings. Unknown values
    # (including exception/provider text) pass through without gettext lookup.
    static_messages = {
        "Token ist abgelaufen. Bitte erneut anmelden.",
        "Ungültiges oder fehlendes Token.",
        "Zu viele Versuche. Bitte später erneut versuchen.",
        "Ungültige Anfrage (JSON erwartet).",
        "Ungültige Anfrage (JSON-Objekt erwartet).",
        "Bitte Benutzername und Passwort angeben.",
        "Falscher Benutzername, Passwort oder Subdomain.",
        "EduPage verlangt ein Captcha. Bitte einmal im Browser anmelden, dann erneut versuchen.",
        "Bitte Zwischen-Token und Code angeben.",
        "Zwischenschritt abgelaufen. Bitte erneut anmelden.",
        "Der Code wurde nicht akzeptiert. Bitte erneut versuchen.",
        "Sitzung erfordert erneut 2FA. Bitte erneut über /auth/login anmelden.",
        "Anmeldung erfordert Zwei-Faktor-Code. Bitte über /auth/login erneut anmelden.",
        "Ungültiger Wahrheitswert (0 oder 1 erwartet).",
        "Ungültiger Wahrheitswert (true/false erwartet).",
        "Ungültiges Datum (YYYY-MM-DD erwartet).",
        "Bitte Token-ID angeben.",
        "Token nicht gefunden.",
        "Datum muss im Format JJJJ-MM-TT sein.",
        "Bitte mindestens einen gültigen Empfänger angeben.",
        "Bitte mindestens einen Empfänger wählen.",
        "Bitte einen Nachrichtentext eingeben.",
        "Gesendet, aber die neue Nachricht wurde nicht gefunden.",
        "Bitte event_id und idx als Zahl angeben.",
        "Nachricht nicht gefunden.",
        "Keine Nachricht ausgewählt.",
        "Datei nicht gefunden.",
        "Ungültiger Download-Link.",
        "Ungültiger Status (alle, offen, überfällig, erledigt oder papierkorb erwartet).",
        "Sitzung abgelaufen. Bitte erneut anmelden.",
        "Hausaufgabe nicht gefunden.",
        "Bitte Koordinaten (?lat=..&lon=..) oder Stadt (?city=..) angeben.",
        "Wetter derzeit nicht verfügbar.",
        "Stadtsuche nicht verfügbar.",
        "Vertretungsplan konnte nicht geladen werden.",
        "Der Zeitraum darf höchstens ein Jahr umfassen.",
        "Schultermine konnten nicht geladen werden.",
        "EduPage meldet: nicht angemeldet.",
        "Limit und Offset müssen ganze Zahlen sein.",
        "Offset darf nicht negativ sein.",
        "Sicherheitsprüfung fehlgeschlagen. Bitte Seite neu laden und erneut versuchen.",
        "Bitte Benutzername und Passwort eingeben.",
        "EduFlow verlangt ein Captcha. Bitte einmal im Browser anmelden, dann erneut versuchen.",
        "2FA-Sitzung abgelaufen. Bitte erneut anmelden.",
        "Anmeldung abgelaufen. Bitte erneut anmelden.",
        "Nicht angemeldet. Bitte erneut anmelden.",
        "Bitte den 2FA-Code aus E-Mail / App eingeben.",
        "Keine Aufgabe ausgewählt.",
        "Als erledigt markiert.",
        "Wieder geöffnet.",
        "Aufgabe in den Papierkorb verschoben.",
        "Aufgabe aus dem Papierkorb geholt.",
        "Aufgabe aus dem Papierkorb geholt und als offen markiert.",
        "Einstellungen gespeichert.",
        "Neuer API-Token erstellt – jetzt kopieren, er wird nur einmal gezeigt.",
        "Kein Token ausgewählt.",
        "API-Token widerrufen.",
        "Antwort gesendet.",
        "Nachricht gesendet.",
        "Nichts Neues – alles bereits gelesen.",
        "Diese Sprache ist noch nicht verfügbar.",
        "Anmeldung fehlgeschlagen:",
        "Download fehlgeschlagen:",
        "Hausaufgaben konnten nicht geladen werden:",
        "Noten konnten nicht geladen werden:",
        "Nachrichten konnten nicht geladen werden:",
        "Thread konnte nicht geladen werden:",
        "Antwort fehlgeschlagen:",
        "Senden fehlgeschlagen:",
        "Empfänger konnten nicht geladen werden:",
        "Einstellungen konnten nicht gespeichert werden:",
        "Cache konnte nicht gelöscht werden:",
        "Stundenplan konnte nicht geladen werden:",
        "Geräte konnten nicht geladen werden:",
        "Bitte einen Antworttext eingeben.",
        "Aufgabe konnte nicht als offen markiert werden:",
        "EduPage verlangt ein Captcha. Bitte einmal im Browser anmelden.",
        "Anmeldung ungültig. Bitte erneut anmelden.",
        "Sitzung erfordert erneut 2FA. Bitte erneut anmelden.",
        "Bitte mindestens einen gültigen Empfänger angeben.",
        "Bitte einen Nachrichtentext eingeben.",
        "Dieser Zeitraum ist nicht verfügbar.",
        "Konnte Hausaufgaben nicht laden:",
        "Konnte Noten nicht laden:",
    }
    if message in static_messages:
        return translate_static(message)
    return message


def _translated_text(value: str, translate: Callable[[str], str]) -> str:
    if not value or not value.strip():
        return value
    leading = value[:len(value) - len(value.lstrip())]
    trailing = value[len(value.rstrip()):]
    middle = value[len(leading):len(value) - len(trailing) if trailing else None]
    source = html.unescape(middle)
    translated = str(translate(source))
    if translated == source:
        return value
    return leading + html.escape(translated, quote=False) + trailing


def _translated_tag(
    tag: str,
    translate: Callable[[str], str],
    offset_base: int = 0,
    on_message: Optional[Callable[[int, str], None]] = None,
) -> str:
    # A complete static tag has no Jinja values. Do not inspect or translate
    # tags containing literal template delimiters (for example inside a raw
    # block) or any attribute outside the explicit UI/accessibility allowlist.
    if "{{" in tag or "}}" in tag or "{%" in tag:
        return tag

    changed = False

    def replace(match: re.Match) -> str:
        nonlocal changed
        name = match.group("name")
        if name.lower() not in _TRANSLATABLE_ATTRIBUTES:
            return match.group(0)
        source = html.unescape(match.group("value"))
        if on_message and source.strip():
            on_message(offset_base + match.start("value"), source)
        translated = str(translate(source))
        if translated == source:
            return match.group(0)
        changed = True
        return (match.group("prefix") + name + match.group("between")
                + match.group("quote")
                + html.escape(translated, quote=True)
                + match.group("quote"))

    result = _ATTRIBUTE.sub(replace, tag)
    return result if changed else tag


def _find_tag_end(
    value: str,
    start: int,
    quote: Optional[str] = None,
    starts_tag: bool = False,
) -> Tuple[Optional[int], Optional[str]]:
    """Find `>` while retaining quote state if a Jinja node split the tag."""
    index = start + 1 if starts_tag else start
    while index < len(value):
        character = value[index]
        if quote:
            if character == quote:
                quote = None
        elif character in "\"'":
            quote = character
        elif character == ">":
            return index + 1, None
        index += 1
    return None, quote


def _scan_markup(
    fragment: str,
    in_tag: bool = False,
    tag_quote: Optional[str] = None,
    raw_element: Optional[str] = None,
    translate: Optional[Callable[[str], str]] = None,
    on_message: Optional[Callable[[int, str], None]] = None,
) -> Tuple[str, bool, Optional[str], Optional[str]]:
    """Translate static markup text and carry context across Jinja nodes."""
    translate = translate or (lambda value: value)
    output = []
    index = 0
    text_start = 0

    def emit_text(start: int, end: int) -> None:
        if end <= start:
            return
        value = fragment[start:end]
        output.append(_translated_text(value, translate))
        if on_message and value.strip():
            leading = len(value) - len(value.lstrip())
            trailing = len(value.rstrip())
            middle = value[leading:trailing]
            message = html.unescape(middle)
            if message:
                on_message(start + leading, message)

    while index < len(fragment):
        if raw_element:
            closing = re.search(
                r"</\s*" + re.escape(raw_element) + r"\b",
                fragment[index:], re.I,
            )
            if not closing:
                output.append(fragment[index:])
                return "".join(output), in_tag, tag_quote, raw_element
            closing_index = index + closing.start()
            output.append(fragment[index:closing_index])
            index = closing_index
            raw_element = None
            in_tag = False
            tag_quote = None
            text_start = index

        if in_tag:
            end, next_quote = _find_tag_end(
                fragment, index, quote=tag_quote,
            )
            if end is None:
                output.append(fragment[index:])
                return "".join(output), True, next_quote, raw_element
            output.append(fragment[index:end])
            index = end
            in_tag = False
            tag_quote = None
            text_start = index
            continue

        if fragment.startswith("<!--", index):
            emit_text(text_start, index)
            end = fragment.find("-->", index + 4)
            if end < 0:
                output.append(fragment[index:])
                return "".join(output), False, None, raw_element
            output.append(fragment[index:end + 3])
            index = end + 3
            text_start = index
            continue

        if fragment[index] == "<" and _TAG_START.match(fragment, index):
            emit_text(text_start, index)
            end, next_quote = _find_tag_end(fragment, index, starts_tag=True)
            if end is None:
                output.append(fragment[index:])
                return "".join(output), True, next_quote, raw_element
            tag = fragment[index:end]
            match = _TAG_START.match(tag)
            tag_name = match.group(1).lower() if match else ""
            is_closing = tag.startswith("</")
            output.append(
                tag if is_closing else _translated_tag(
                    tag, translate, offset_base=index, on_message=on_message,
                )
            )
            if not is_closing and tag_name in _RAW_ELEMENTS and not tag.rstrip().endswith("/>"):
                raw_element = tag_name
            index = end
            text_start = index
            continue

        if fragment[index] == "<" and index + 1 < len(fragment) and fragment[index + 1] in "!?":
            emit_text(text_start, index)
            end, next_quote = _find_tag_end(fragment, index, starts_tag=True)
            if end is None:
                output.append(fragment[index:])
                return "".join(output), False, None, raw_element
            output.append(fragment[index:end])
            index = end
            text_start = index
            continue

        index += 1

    emit_text(text_start, len(fragment))
    return "".join(output), in_tag, tag_quote, raw_element


def _l10n_markup(
    fragment: str,
    in_tag: bool = False,
    tag_quote: str = "",
    raw_element: str = "",
) -> Markup:
    translate = translate_static

    rendered, _in_tag, _tag_quote, _raw_element = _scan_markup(
        fragment,
        in_tag=in_tag,
        tag_quote=tag_quote or None,
        raw_element=raw_element or None,
        translate=translate,
    )
    # The scanner escapes translated text/attributes and leaves original markup
    # unchanged; mark the result safe so Jinja does not escape the HTML tags.
    return Markup(rendered)


class TemplateTextTranslationExtension(Extension):
    """Pass only literal HTML token data through gettext at render time."""

    def filter_stream(self, stream):
        in_tag = False
        tag_quote = None
        raw_element = None
        for token in stream:
            if token.type != "data":
                yield token
                continue

            source = token.value
            start_in_tag = in_tag
            start_tag_quote = tag_quote
            start_raw_element = raw_element
            _unchanged, in_tag, tag_quote, raw_element = _scan_markup(
                source,
                in_tag=in_tag,
                tag_quote=tag_quote,
                raw_element=raw_element,
            )

            yield Token(token.lineno, "variable_begin", "{{")
            yield Token(token.lineno, "name", "_l10n_markup")
            yield Token(token.lineno, "lparen", "(")
            yield Token(token.lineno, "string", source)
            yield Token(token.lineno, "comma", ",")
            yield Token(token.lineno, "name", "in_tag")
            yield Token(token.lineno, "assign", "=")
            yield Token(token.lineno, "name", "true" if start_in_tag else "false")
            yield Token(token.lineno, "comma", ",")
            yield Token(token.lineno, "name", "tag_quote")
            yield Token(token.lineno, "assign", "=")
            yield Token(token.lineno, "string", start_tag_quote or "")
            yield Token(token.lineno, "comma", ",")
            yield Token(token.lineno, "name", "raw_element")
            yield Token(token.lineno, "assign", "=")
            yield Token(token.lineno, "string", start_raw_element or "")
            yield Token(token.lineno, "rparen", ")")
            yield Token(token.lineno, "variable_end", "}}")


def extract_template_messages(fileobj, keywords, comment_tags, options):
    """Babel extractor for gettext calls plus literal HTML text/attributes."""
    source = fileobj.read()
    if isinstance(source, bytes):
        source = source.decode(options.get("encoding", "utf-8"))

    # Keep normal Jinja gettext() calls and `{% trans %}` extraction working.
    from io import BytesIO
    messages = list(babel_extract(
        BytesIO(source.encode(options.get("encoding", "utf-8"))),
        keywords, comment_tags, options,
    ))
    seen = {(line, str(message)) for line, _func, message, _comments in messages}
    yield from messages

    in_tag = False
    tag_quote = None
    raw_element = None
    environment = Environment()
    for line, token_type, value in environment.lex(source):
        if token_type != "data":
            continue
        token_messages = []

        def emit(_offset: int, message: str) -> None:
            message_line = line + value[:_offset].count(chr(10))
            token_messages.append((message_line, message))

        _ignored, in_tag, tag_quote, raw_element = _scan_markup(
            value,
            in_tag=in_tag,
            tag_quote=tag_quote,
            raw_element=raw_element,
            on_message=emit,
        )
        for message_line, message in token_messages:
            key = (message_line, message)
            if key not in seen:
                seen.add(key)
                yield message_line, "gettext", message, []
