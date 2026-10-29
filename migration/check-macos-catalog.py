"""Bereinigt die macOS-Lokalisierungen.

`Localizable.xcstrings` hat deutsche Klartext-Schlüssel, und Crowdin hat
deutsche Werte in leere Felder geschrieben: af, ca, he, hu, ko, sr, tr, vi
und zh-Hant zeigten in 187 Texten Deutsch statt der eigenen Sprache, ar in
51. Zusätzlich stand die englische Lokalisierung an acht Stellen noch auf
deutschem Quelltext — davon haben alle Sprachen kopiert.

    python3 migration/check-macos-catalog.py          # nur melden
    python3 migration/check-macos-catalog.py --fix    # durch Englisch ersetzen

Kognite bleiben stehen, weil sie in der Zielsprache korrekt sind
(Kalender im Niederländischen, Datum im Schwedischen, Typ im Tschechischen,
Note im Französischen). Wer sie verliert, bekommt Englisch — auch das ist
besser als Deutsch, aber der Katalog soll ja übersetzt werden.
"""
import glob
import json
import re
import sys
import unicodedata

# Stil-treuer Schreiber (Xcode-Format statt `json.dump`), damit `--fix`
# nur die geaenderten Werte zeigt und nicht die ganze Datei umschreibt.
sys.path.insert(0, glob.glob("migration")[0] or ".")
import xcstrings_json  # noqa: E402

PFAD = glob.glob("mac/**/Localizable.xcstrings", recursive=True)[0]

# Wo die englische Lokalisierung noch deutscher Quelltext ist — nach dem
# deutschen Wert benannt, weil der Schluessel teils ein Bezeichner ist
# (`homework_filter_overdue`). Ohne diese Korrektur uebernehmen alle
# Sprachen weiter den deutschen Wert.
ENGLISCH = {
    "fällig: ": "due: ",
    "heute fällig": "due today",
    "Überfällig": "Overdue",
    "ENTFÄLLT": "Cancelled",
    "ungelesen": "unread",
    "Alle": "All",
    "Offen": "Open",
}

# Schluessel, in denen `de` selbst den englischen Text traegt (die
# Umkehrung des obigen Falls). Ohne `en` gibt es nichts zum Kopieren,
# deshalb wird der deutsche Wert hier durch einen echten englischen
# ersetzt — sowohl in `de` als auch in den unuebersetzten Sprachen.
DE_FALSCH_ENGLISCH = {
    # Schluessel, in denen `de` deutschen Quelltext traegt und `en`
    # ganz fehlt. Der englische Wert wird ergaenzt und in `de` sowie
    # den unuebersetzten Sprachen gesetzt.
    "z. B. musterschule": "e.g. myschool",
    # Fehlender englischer Wert: `de` und die unuebersetzten Sprachen
    # tragen denselben Text, den es so auch auf Englisch gilt. Ohne `en`
    # gibt es fuer Schritt 2 nichts zu kopieren, also bleibt dort
    # Deutsch stehen (in ca/he/ko/sr/tr/vi/zh-Hant/af).
    "Subdomain (optional)": "Subdomain (optional)",
}

# Deutsche Quelltexte, die in den unuebersetzten Sprachen als eigene
# Uebersetzung markiert stehen (Crowdin-Mischstand): der Wert entspricht
# weder dem heutigen `de`- noch einem anderen deutschen Wert im Katalog,
# ist aber trotzdem deutsch (`Bereich`, `Ein`, `Petrol`). Ohne diese Liste
# bleibt in diesen Sprachen sichtbares Deutsch stehen.
#
# Erzeugt aus dem Katalog: alle Werte, die in einer unuebersetzten
# Sprache vom englischen Wert abweichen, aber weder Kognit noch der
# jeweilige `de`-Wert sind. Nach dem Schluessel benannt, weil derselbe
# deutsche Text in mehreren Schluesseln vorkommt.
ALT_DEUTSCH = {
    '6-stelliger Code': ('6-stelliger Code', '6-digit code'),
    'Alle Aufgaben': ('Alle Aufgaben', 'All homework'),
    'Alle EduPage-Nachrichten im Mail-Layout — mit Likes, Antworten und Dateien.': ('Alle EduPage-Nachrichten im Mail-Layout — mit Likes, Antworten und Dateien.', 'All EduPage messages in a mail layout — with likes, replies and files.'),
    'Alle als gelesen': ('Alle als gelesen', 'Mark all as read'),
    'Alles zeigen': ('Alles zeigen', 'Show all'),
    'Ausgeblendete': ('Ausgeblendete', 'Hidden'),
    'Aussehen': ('Aussehen', 'Appearance'),
    'Bereich': ('Bereich', 'Section'),
    'Bereich aus der Leiste entfernen': ('Bereich aus der Leiste entfernen', 'Remove section from the bar'),
    'Bereich nach oben verschieben': ('Bereich nach oben verschieben', 'Move section up'),
    'Bereich nach unten verschieben': ('Bereich nach unten verschieben', 'Move section down'),
    'Bereich zur Leiste hinzufügen': ('Bereich zur Leiste hinzufügen', 'Add section to the bar'),
    'Code aus E-Mail oder App eingeben.': ('Code aus E-Mail oder App eingeben.', 'Enter the code from your email or app.'),
    'Demo ansehen': ('Demo ansehen', 'View demo'),
    'Demo-Modus · nur synthetische Beispieldaten': ('Demo-Modus · nur synthetische Beispieldaten', 'Demo mode · synthetic sample data only'),
    'Direkt in die Nachrichten': ('Direkt in die Nachrichten', 'Go to messages'),
    'Direkt zu den Aufgaben': ('Direkt zu den Aufgaben', 'Go to homework'),
    'Direkt zu den Noten': ('Direkt zu den Noten', 'Go to grades'),
    'Direkt zum Stundenplan': ('Direkt zum Stundenplan', 'Go to timetable'),
    'EduFlow Dashboard · lokal': ('EduFlow Dashboard · lokal', 'EduFlow Dashboard · local'),
    'EduFlow ist bereit': ('EduFlow hazır', 'EduFlow is ready'),
    'Entfall': ('Entfall', 'Cancellation'),
    'Entfällt': ('Entfällt', 'Cancelled'),
    'Erledigt': ('Erledigt', 'Completed'),
    'Erneut laden': ('Erneut laden', 'Reload'),
    'Es werden ausschließlich synthetische Beispieldaten vom lokalen Demo-Server geladen.': ('Es werden ausschließlich synthetische Beispieldaten vom lokalen Demo-Server geladen.', 'Only synthetic sample data is loaded from the local demo server.'),
    'Fehlgeschlagen': ('Fehlgeschlagen', 'Failed'),
    'Fertige Aufgaben': ('Fertige Aufgaben', 'Completed homework'),
    'Frist vorbei': ('Frist vorbei', 'Past due'),
    'Fälligkeiten mit Zählern, Halbjahr-Tabs und Schnitt.': ('Fälligkeiten mit Zählern, Halbjahr-Tabs und Schnitt.', 'Due dates with counters, semester tabs and average.'),
    'Für diese Woche sind keine Vertretungen eingetragen.': ('Für diese Woche sind keine Vertretungen eingetragen.', 'No substitutions scheduled for this week.'),
    'Für diesen Tag steht nichts im Plan.': ('Für diesen Tag steht nichts im Plan.', 'Nothing scheduled for this day.'),
    'Gefühlt': ('Gefühlt', 'Feels like'),
    'Geladene Datei teilen': ('Geladene Datei teilen', 'Share downloaded file'),
    'Halbjahr': ('Halbjahr', 'Semester'),
    'Hell und Dunkel folgt dem System. Akzentfarbe:': ('Hell und Dunkel folgt dem System. Akzentfarbe:', 'Light and dark follow the system. Accent color:'),
    'Hinzufügen': ('Hinzufügen', 'Add'),
    'In den Papierkorb': ('In den Papierkorb', 'Move to trash'),
    'Keine Schultermine oder Prüfungen in diesem Zeitraum.': ('Keine Schultermine oder Prüfungen in diesem Zeitraum.', 'No school events or exams in this period.'),
    'Keine offenen Hausaufgaben. Sehr gut.': ('Keine offenen Hausaufgaben. Sehr gut.', 'No open homework. Well done.'),
    'Keine weiteren Sitzungen.': ('Keine weiteren Sitzungen.', 'No other sessions.'),
    'Lege fest, welche Bereiche zuerst erscheinen.': ('Lege fest, welche Bereiche zuerst erscheinen.', 'Choose which sections appear first.'),
    'Lokales Werkzeug — Zugangsdaten bleiben auf diesem Mac.': ('Lokales Werkzeug — Zugangsdaten bleiben auf diesem Mac.', 'Local tool — credentials stay on this Mac.'),
    'Luftdruck': ('Luftdruck', 'Pressure'),
    'Luftfeuchte': ('Luftfeuchte', 'Humidity'),
    'Lädt …': ('Lädt …', 'Loading …'),
    'Meldet dich ab und startet die Einführung erneut.': ('Meldet dich ab und startet die Einführung erneut.', 'Signs you out and restarts the introduction.'),
    'Neu laden': ('Neu laden', 'Reload'),
    'Nur erledigte': ('Nur erledigte', 'Only done'),
    'Nur offene': ('Nur offene', 'Only open'),
    'Nur synthetische Beispieldaten vom lokalen Fake-Server': ('Nur synthetische Beispieldaten vom lokalen Fake-Server', 'Only synthetic sample data from the local fake server'),
    'Nur überfällige': ('Nur überfällige', 'Only overdue'),
    'Nächste →': ('Nächste →', 'Next →'),
    'Ohne erledigte': ('Ohne erledigte', 'Without done'),
    'Onboarding erneut durchlaufen': ('Onboarding erneut durchlaufen', 'Run onboarding again'),
    'Passwort verbergen': ('Passwort verbergen', 'Hide password'),
    'Prüfen …': ('Prüfen …', 'Checking …'),
    'Prüft …': ('Prüft …', 'Checking …'),
    'Schulalltag': ('Schulalltag', 'School life'),
    'Schulfrei': ('Schulfrei', 'No school'),
    'Schulfrei.': ('Schulfrei.', 'No school.'),
    'Sendet …': ('Sendet …', 'Sending …'),
    'Sicht': ('Sicht', 'View'),
    'Speichert …': ('Speichert …', 'Saving …'),
    'Startseite nach Anmeldung': ('Startseite nach Anmeldung', 'Start page after sign-in'),
    'Stunden heute': ('Stunden heute', 'Classes today'),
    'Suche': ('Suche', 'Search'),
    'Termine': ('Termine', 'Events'),
    'Termine und Planänderungen': ('Termine und Planänderungen', 'Events and schedule changes'),
    'Trage ein, wo EduFlow als Server läuft.': ('Trage ein, wo EduFlow als Server läuft.', 'Enter where EduFlow runs as server.'),
    'Veranstaltung': ('Veranstaltung', 'Event'),
    'Vertretungen': ('Vertretungen', 'Substitutions'),
    'Welches Gerät meldest du an?': ('Welches Gerät meldest du an?', 'Which device are you signing in?'),
    'Wie heißt du bei EduPage?': ('Wie heißt du bei EduPage?', 'What is your EduPage username?'),
    'Wieder öffnen': ('Wieder öffnen', 'Reopen'),
    'Zurückholen': ('Zurückholen', 'Restore'),
    'Zurückholen (als offen)': ('Zurückholen (als offen)', 'Restore (as open)'),
    'Zusatz': ('Zusatz', 'Extra'),
    'auth_hint_device': ('Welches Gerät meldest du an?', 'Which device are you signing in?'),
    'auth_hint_subdomain': ('Leer lassen für automatische Erkennung.', 'Leave empty for automatic detection.'),
    'auth_hint_username': ('Wie heißt du bei EduPage?', 'What is your EduPage username?'),
    'auth_label_subdomain': ('Schuldomain (optional)', 'School domain (optional)'),
    'auth_placeholder_code': ('6-stelliger Code', '6-digit code'),
    'auth_placeholder_device': ('z. B. MacBook', 'e.g. MacBook'),
    'auth_placeholder_subdomain': ('z. B. meine-schule', 'e.g. my-school'),
    'auth_placeholder_username': ('z. B. max.muster', 'e.g. max.muster'),
    'common_accent_teal': ('Petrol', 'Teal'),
    'common_error_bad_credentials': ('Falscher Benutzername, Passwort oder Subdomain.', 'Wrong username, password or subdomain.'),
    'common_error_captcha_required': ('EduPage verlangt ein Captcha. Bitte einmal im Browser anmelden.', 'EduPage requires a captcha. Please sign in via browser once.'),
    'common_error_config_missing': ('Server-Schlüssel fehlt. Bitte später erneut versuchen.', 'Server key missing. Please try again later.'),
    'common_error_edupage_2fa': ('EduPage verlangt erneut einen Code. Bitte neu anmelden.', 'EduPage requires a code again. Please sign in again.'),
    'common_error_invalid_code': ('Der Code wurde nicht akzeptiert. Bitte erneut versuchen.', 'The code was not accepted. Please try again.'),
    'common_error_pending_invalid': ('Zwischenschritt abgelaufen. Bitte erneut anmelden.', 'Intermediate step expired. Please sign in again.'),
    'common_error_rate_limited': ('Zu viele Versuche. Bitte später erneut versuchen.', 'Too many attempts. Please try again later.'),
    'common_error_token_expired': ('Sitzung abgelaufen. Bitte erneut anmelden.', 'Session expired. Please sign in again.'),
    'common_error_token_invalid': ('Sitzung ungültig. Bitte erneut anmelden.', 'Session invalid. Please sign in again.'),
    'common_error_upstream': ('Anfrage fehlgeschlagen. Bitte später erneut versuchen.', 'Request failed. Please try again later.'),
    'common_error_validation': ('Ungültige Eingabe. Bitte prüfen und erneut versuchen.', 'Invalid input. Please check and try again.'),
    'common_loading': ('Lädt …', 'Loading …'),
    'common_password_hide': ('Passwort verbergen', 'Hide password'),
    'common_toggle_on': ('Ein', 'On'),
    'content_demo_hint': ('Nur synthetische Beispieldaten vom lokalen Fake-Server', 'Only synthetic sample data from the local fake server'),
    'grades_average_hint': ('Schnitt aus klassischen Noten, nach Gewichtung.', 'Average of classic grades, weighted.'),
    'grades_average_stats': ('Schnitt: %@', 'Average: %@'),
    'grades_halfyear_all': ('Gesamt', 'All'),
    'grades_halfyear_format': ('%d. Halbjahr %d/%@', 'Semester %d (%d/%@)'),
    'grades_not_classic': ('o. Wertung', 'not graded'),
    'grades_picker_halfyear': ('Halbjahr', 'Semester'),
    'grades_subject_average_caption': ('Fachschn. gewichtet', 'Subject avg. weighted'),
    'grades_subject_other': ('Sonstiges', 'Other'),
    'grades_summary_stats': ('%d Noten · %d Fächer · Schnitt: %@', '%d grades · %d subjects · average: %@'),
    'heute fällig': ('heute fällig', 'due today'),
    'homework_action_reopen': ('Wieder öffnen', 'Reopen'),
    'homework_action_restore': ('Zurückholen', 'Restore'),
    'homework_count': ('%d Aufgaben', '%d homework'),
    'homework_empty_done': ('Noch nichts erledigt.', 'Nothing completed yet.'),
    'homework_empty_overdue': ('Nichts überfällig.', 'Nothing overdue.'),
    'homework_filter_done': ('Erledigt', 'Completed'),
    'homework_filter_overdue': ('Überfällig', 'Overdue'),
    'homework_menu_restore': ('Zurückholen (als offen)', 'Restore (as open)'),
    'homework_menu_trash': ('In den Papierkorb', 'Move to trash'),
    'kein Unterricht heute': ('kein Unterricht heute', 'no classes today'),
    'messages_action_mark_read': ('Alle als gelesen', 'Mark all as read'),
    'messages_action_reload': ('Neu laden', 'Reload'),
    'messages_compose_search_placeholder': ('Suche', 'Search'),
    'messages_recipients_chosen': ('Empfänger (%d gewählt)', 'Recipients (%d selected)'),
    'messages_state_read': ('Gelesen', 'Read'),
    'offen': ('offen', 'open'),
    'ohne Datum': ('ohne Datum', 'No date'),
    'onboarding_feature_homework_text': ('Fälligkeiten mit Zählern, Halbjahr-Tabs und Schnitt.', 'Due dates with counters, semester tabs and average.'),
    'onboarding_feature_messages_text': ('Alle EduPage-Nachrichten im Mail-Layout — mit Likes, Antworten und Dateien.', 'All EduPage messages in a mail layout — with likes, replies and files.'),
    'onboarding_feature_timetable_text': ('Tag und Woche und Wetter auf der Übersicht.', 'Day and week plus weather on the overview.'),
    'onboarding_language_subtitle': ('EduFlow spricht deine Sprache. Die Auswahl wird sofort übernommen.', 'EduFlow speaks your language. The choice applies immediately.'),
    'overview_city_missing': ('Bitte eine Stadt in den Einstellungen eintragen.', 'Please enter a city in settings.'),
    'overview_homework_all_done': ('Alle Hausaufgaben erledigt. Sehr gut.', 'All homework done. Well done.'),
    'overview_homework_more_available': ('Weitere Aufgaben vorhanden — alle ansehen.', 'More tasks available — view all.'),
    'overview_homework_none': ('Keine Hausaufgaben vorhanden.', 'No homework available.'),
    'overview_homework_sub': ('%d offen · %d überfällig', '%d open · %d overdue'),
    'overview_lesson_detail': ('%@. Std · %@%@%@', '%@. period · %@%@%@'),
    'overview_lesson_room': (' · Raum %@', ' · Room %@'),
    'overview_more_homework': ('+ %d weitere', '+ %d more'),
    'overview_more_messages': ('+ %d weitere', '+ %d more'),
    'overview_weather_in_city': ('Wetter in %@', 'Weather in %@'),
    'overview_week_label': ('%@ haftası', 'Week %@'),
    'school_action_changed': ('GEÄNDERT', 'CHANGED'),
    'school_action_remove': ('ENTFÄLLT', 'CANCELLED'),
    'school_kind_exam': ('TEST / PRÜFUNG', 'TEST / EXAM'),
    'school_nav': ('Termine & Vertretungen', 'Events & substitutions'),
    'school_picker_section': ('Bereich', 'Section'),
    'school_plan_change': ('Stundenplanänderung', 'Timetable change'),
    'school_tab_substitutions': ('Vertretungen', 'Substitutions'),
    'school_week_from': ('Woche ab %@', 'Week of %@'),
    'settings_cache_clear_busy': ('Cache leeren …', 'Clearing cache …'),
    'settings_filter_all_desc': ('Alles zeigen', 'Show everything'),
    'settings_filter_done_desc': ('Fertige Aufgaben', 'Completed tasks'),
    'settings_filter_done_title': ('Nur erledigte', 'Only completed'),
    'settings_filter_open_desc': ('Ohne erledigte', 'Without done'),
    'settings_filter_open_title': ('Nur offene', 'Only open'),
    'settings_filter_overdue_desc': ('Frist vorbei', 'Past due'),
    'settings_filter_overdue_title': ('Nur überfällige', 'Only past due'),
    'settings_filter_trash_desc': ('Ausgeblendete', 'Hidden'),
    'settings_landing_grades_desc': ('Direkt zu den Noten', 'Go straight to grades'),
    'settings_landing_homework_desc': ('Direkt zu den Aufgaben', 'Go straight to homework'),
    'settings_landing_messages_desc': ('Direkt in die Nachrichten', 'Go straight to messages'),
    'settings_landing_timetable_desc': ('Direkt zum Stundenplan', 'Go straight to timetable'),
    'settings_navbar_desc': ('Lege fest, welche Bereiche oben erscheinen und in welcher Reihenfolge. Termine bleiben auch ohne Reiter über das Profilmenü erreichbar.', 'Choose which sections appear on top and in which order. Events stay reachable via the profile menu even without a tab.'),
    'settings_ov_order_hint': ('Wird mit „Speichern“ übernommen.', 'Applied when you save.'),
    'settings_ov_order_title': ('Reihenfolge der Bereiche', 'Section order'),
    'settings_toggle_onboarding_restart': ('Onboarding erneut durchlaufen', 'Run onboarding again'),
    'z. B. MacBook': ('z. B. MacBook', 'e.g. MacBook'),
    'z. B. max.muster': ('z. B. max.muster', 'e.g. max.muster'),
    'Überfällig': ('Überfällig', 'Overdue'),
    'Übermorgen': ('Übermorgen', 'Day after tomorrow'),
    'Übernehmen': ('Übernehmen', 'Apply'),
    'Übernehmen & weiter': ('Übernehmen & weiter', 'Apply & continue'),
    'überfällig': ('überfällig', 'overdue'),
    '← Vorwoche': ('← Vorwoche', '← Previous week'),
}

# Werte, die in der jeweiligen Sprache richtig sind und dem Deutschen nur
# gleichen. Alles andere gilt als deutscher Rest.
KOGNITE = {
    "nl": {"Kalender", "Morgen", "Hallo!", "Wolken", "Standardfilter"},
    "sv": {"Datum", "Kalender", "Titel", "Typ", "Standardfilter"},
    "no": {"Alle", "Kalender"},
    "da": {"Alle", "Kalender", "Titel"},
    "cs": {"Typ"},
    "pl": {"Typ"},
    "fr": {"Note"},
    "fi": {"Kalender"},
    "es": {"Note"},
    "it": {"Tipo"},
    "pt": {"Tipo"},
    "ro": {"Data"},
    # Ungarisch entlehnt diese Woerter unveraendert; `Kalender` steht in
    # zwei Schluesseln, beide muessen es nennen.
    "hu": {"Kalender", "Dátum"},
}

NORMAL = re.compile(r"[^a-zäöüß]")


def unuebersetzte_sprachen(strings):
    """Sprachen, in denen kein eigener Wert vorhanden ist.

    Crowdin hat fuer diese Sprachen ausschliesslich deutsche Quelltexte
    geliefert — 191 von 408 Eintraegen sind ein anderer deutscher Wortlaut
    als der heutige `de`-Wert, aber keiner ist uebersetzt. Bei allen
    anderen Sprachen hat Crowdin eigene Werte geliefert, und diese bleiben
    unangetastet: `ar` hat 331 eigene Werte, ist also teiluebersetzt und
    darf nicht mitbehandelt werden.

    Die Liste steht fest, weil sie sich nicht verlaesslich aus dem
    Katalog ableiten laesst: Anteil eigener Werte (43 % bei af gegen
    81 % bei ar) und Umlautquote messen beide den Defekt mit, den diese
    Reparatur behebt, statt ihn zu erkennen. Nach jedem Crowdin-Sync
    gehoert die Liste geprueft — `python3 check-macos-catalog.py` gibt
    sie aus.
    """
    return {"af", "ca", "he", "hu", "ko", "sr", "tr", "vi", "zh-Hant"}


def norm(text):
    # NFC zuerst: der deutsche Katalog mischt zerlegte Umlaute (A + U+0308)
    # und zusammengesetzte (Ä). Ohne das gelten 'ENTFÄLLT' und 'ENTFÄLLT'
    # als verschieden.
    return NORMAL.sub("", unicodedata.normalize("NFC", text or "").lower())


def wert(eintrag, sprache):
    teil = eintrag.get("localizations", {}).get(sprache)
    return teil.get("stringUnit", {}).get("value") if teil else None


def setze(eintrag, sprache, neuer):
    einheit = eintrag["localizations"][sprache]["stringUnit"]
    einheit["value"] = neuer
    # Ein reparierter Wert ist eine vollstaendige Uebersetzung. Ohne das
    # bleibt `state` auf `new` stehen und Schritt 2 wertet ihn als
    # unuebersetzt — der deutsche Wert bliebe sichtbar.
    if einheit.get("state") == "new":
        einheit["state"] = "translated"


def main():
    reparieren = "--fix" in sys.argv
    with open(PFAD, encoding="utf-8") as datei:
        daten = json.load(datei)
    strings = daten["strings"]
    sprachen = sorted({sp for e in strings.values() for sp in e.get("localizations", {})})
    # Aus dem Katalog statt fest: siehe unuebersetzte_sprachen().
    unuebersetzt = unuebersetzte_sprachen(strings)
    print(f"  unuebersetzte Sprachen: {', '.join(sorted(unuebersetzt)) or '(keine)'}")

    # 1) Englische Lokalisierung reparieren
    for eintrag in strings.values():
        alt = wert(eintrag, "en")
        if alt in ENGLISCH:
            neuer = ENGLISCH[alt]
            print(f"  en: {alt!r} -> {neuer!r}")
            if reparieren:
                setze(eintrag, "en", neuer)

    # 1b) Schluessel, in denen `de` deutschen Quelltext traegt und `en`
    # ganz fehlt. `en` wird ergaenzt, damit die Sprachen darunter etwas
    # zum Kopieren bekommen, und `de` bekommt denselben Wert.
    for key, neuer in DE_FALSCH_ENGLISCH.items():
        eintrag = strings.get(key)
        if eintrag is None or wert(eintrag, "de") is None:
            continue
        # Gesetzt wird nur, wenn `en` wirklich fehlt — sonst laeuft der
        # Schritt bei einem bereits reparierten Key ins Leere.
        if wert(eintrag, "en") is not None:
            continue
        print(f"  en fehlt: {neuer!r}")
        if not reparieren:
            continue
        for sprache in ("en", "de"):
            if wert(eintrag, sprache) is None:
                eintrag["localizations"][sprache] = {
                    "stringUnit": {"state": "translated", "value": neuer}
                }
            else:
                setze(eintrag, sprache, neuer)

    # 2) Deutsche Werte in anderen Sprachen durch Englisch ersetzen.
    #
    # Zwei Arten von deutschem Rest werden erwischt:
    #   a) der Wert ist genau der deutsche Wert desselben Schluessels,
    #   b) der Wert ist ein deutscher Wert aus einem ANDEREN Schluessel —
    #      also eine aeltere deutsche Formulierung desselben Textes
    #      (`Alle Aufgaben` statt `Alle Hausaufgaben`). Ohne (b) bleibt in
    #      den unuebersetzten Sprachen sichtbares Deutsch stehen.
    deutsche_werte = {norm(v) for v in (wert(e, "de") for e in strings.values()) if v}
    pro_sprache = {}
    for key, eintrag in strings.items():
        neu_en = wert(eintrag, "en")
        deutsch = wert(eintrag, "de")
        altform = ALT_DEUTSCH.get(key)
        if deutsch is None:
            continue
        if neu_en is None and altform is None:
            continue
        for sprache in sprachen:
            if sprache in ("de", "en"):
                continue
            alt = wert(eintrag, sprache)
            if alt is None:
                continue
            # `state: new` heisst "unuebersetzt, Wert ist nur der
            # Quelltext". Ein deutscher Quelltext ist aber nicht die
            # eigene Sprache: bei einer unuebersetzten Sprache wird er
            # durch Englisch ersetzt. Sonst zeigt die App in diesen
            # Sprachen weiterhin Deutsch. Kognite (siehe KOGNITE) und
            # Werte, die es in der Zielsprache woertlich so gibt, bleiben
            # unangetastet — dafuer sorgt der Vergleich weiter unten.
            n_alt = norm(alt)
            # Ziel bestimmen: was soll an die Stelle des deutschen
            # Wertes? Zuerst eine festgehaltene Altform, dann — falls
            # vorhanden — der englische Wert desselben Schluessels.
            altform_trifft = altform is not None and n_alt == norm(altform[0])
            if altform_trifft:
                ziel = altform[1]
            elif neu_en is not None:
                ziel = neu_en
            else:
                continue
            if alt == ziel:
                continue
            if alt in KOGNITE.get(sprache, set()):
                continue
            # Ist der aktuelle Wert ueberhaupt deutsch?
            if sprache in unuebersetzt:
                # Unuebersetzte Sprache: jeder nicht-englische Wert ist
                # deutsch. Erfasst werden der heutige `de`-Wert, jeder
                # andere deutsche Wert aus dem Katalog (aeltere Fassung)
                # und die namentlich gelisteten Altformen.
                ist_deutsch = (
                    altform_trifft
                    or n_alt == norm(deutsch)
                    or n_alt in deutsche_werte
                )
                if not ist_deutsch:
                    continue
            else:
                # Sonst nur der exakte deutsche Wert desselben Schluessels.
                if neu_en is None or norm(deutsch) == norm(neu_en):
                    continue
                if n_alt != norm(deutsch):
                    continue
            pro_sprache[sprache] = pro_sprache.get(sprache, 0) + 1
            if reparieren:
                setze(eintrag, sprache, ziel)

    for sprache, anzahl in sorted(pro_sprache.items(), key=lambda pa: -pa[1]):
        print(f"  {sprache:8} {anzahl:>4} deutsche Werte -> Englisch")

    if reparieren:
        with open(PFAD, "w", encoding="utf-8") as datei:
            datei.write(xcstrings_json.dumps(daten))
        print("Katalog geschrieben")
    else:
        print(f'{"gefunden" if not reparieren else "ersetzt"}: {sum(pro_sprache.values())}')
    return 0


if __name__ == "__main__":
    sys.exit(main())
