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
    '(keine Beschreibung)': ('(keine Beschreibung)', '(no description)'),
    '(unbekannt)': ('(unbekannt)', '(unknown)'),
    '6-stelliger Code': ('6-stelliger Code', '6-digit code'),
    'Abbrechen': ('Abbrechen', 'Cancel'),
    'Abmelden': ('Abmelden', 'Sign out'),
    'Abmelden …': ('Abmelden …', 'Signing out …'),
    'Alle': ('Alle', 'All'),
    'Alle Aufgaben': ('Alle Aufgaben', 'All homework'),
    'Alle EduPage-Nachrichten im Mail-Layout — mit Likes, Antworten und Dateien.': ('Alle EduPage-Nachrichten im Mail-Layout — mit Likes, Antworten und Dateien.', 'All EduPage messages in a mail layout — with likes, replies and files.'),
    'Alle Nachrichten': ('Alle Nachrichten', 'All messages'),
    'Alle als gelesen': ('Alle als gelesen', 'Mark all as read'),
    'Alles an einem Ort.': ('Alles an einem Ort.', 'Everything in one place.'),
    'Alles zeigen': ('Alles zeigen', 'Show all'),
    'Als erledigt markieren': ('Als erledigt markieren', 'Mark as done'),
    'Anmelden': ('Anmelden', 'Sign in'),
    'Anmelden …': ('Anmelden …', 'Signing in …'),
    'Antwort schreiben': ('Antwort schreiben', 'Write a reply'),
    'Antworten': ('Antworten', 'Replies'),
    'Ausgeblendete': ('Ausgeblendete', 'Hidden'),
    'Aussehen': ('Aussehen', 'Appearance'),
    'Basis-URL': ('Basis-URL', 'Base URL'),
    'Benutzername': ('Benutzername', 'Username'),
    'Bereich': ('Bereich', 'Section'),
    'Bereich aus der Leiste entfernen': ('Bereich aus der Leiste entfernen', 'Remove section from the bar'),
    'Bereich nach oben verschieben': ('Bereich nach oben verschieben', 'Move section up'),
    'Bereich nach unten verschieben': ('Bereich nach unten verschieben', 'Move section down'),
    'Bereich zur Leiste hinzufügen': ('Bereich zur Leiste hinzufügen', 'Add section to the bar'),
    'Bestätigen': ('Bestätigen', 'Confirm'),
    'Code aus E-Mail oder App eingeben.': ('Code aus E-Mail oder App eingeben.', 'Enter the code from your email or app.'),
    'Code eingeben': ('Code eingeben', 'Enter code'),
    'Dateien': ('Dateien', 'Files'),
    'Datum': ('Datum', 'Date'),
    'Dein Profil': ('Dein Profil', 'Your profile'),
    'Demo ansehen': ('Demo ansehen', 'View demo'),
    'Demo verlassen': ('Demo verlassen', 'Leave demo'),
    'Demo-Modus': ('Demo-Modus', 'Demo mode'),
    'Demo-Modus · nur synthetische Beispieldaten': ('Demo-Modus · nur synthetische Beispieldaten', 'Demo mode · synthetic sample data only'),
    'Dienstag': ('Dienstag', 'Tuesday'),
    'Direkt in die Nachrichten': ('Direkt in die Nachrichten', 'Go to messages'),
    'Direkt zu den Aufgaben': ('Direkt zu den Aufgaben', 'Go to homework'),
    'Direkt zu den Noten': ('Direkt zu den Noten', 'Go to grades'),
    'Direkt zum Stundenplan': ('Direkt zum Stundenplan', 'Go to timetable'),
    'Donnerstag': ('Donnerstag', 'Thursday'),
    'EduFlow Dashboard · lokal': ('EduFlow Dashboard · lokal', 'EduFlow Dashboard · local'),
    'EduFlow ist bereit': ('EduFlow hazır', 'EduFlow is ready'),
    'Einstellungen': ('Einstellungen', 'Settings'),
    'Entfall': ('Entfall', 'Cancellation'),
    'Entfernen': ('Entfernen', 'Remove'),
    'Entfällt': ('Entfällt', 'Cancelled'),
    'Entwickleroptionen': ('Entwickleroptionen', 'Developer options'),
    'Entwickleroptionen aktivieren': ('Entwickleroptionen aktivieren', 'Enable developer options'),
    'Erledigt': ('Erledigt', 'Completed'),
    'Erneut laden': ('Erneut laden', 'Reload'),
    'Erneut versuchen': ('Erneut versuchen', 'Try again'),
    'Es werden ausschließlich synthetische Beispieldaten vom lokalen Demo-Server geladen.': ('Es werden ausschließlich synthetische Beispieldaten vom lokalen Demo-Server geladen.', 'Only synthetic sample data is loaded from the local demo server.'),
    'Fehlgeschlagen': ('Fehlgeschlagen', 'Failed'),
    'Fertig': ('Fertig', 'Done'),
    'Fertige Aufgaben': ('Fertige Aufgaben', 'Completed homework'),
    'Freitag': ('Freitag', 'Friday'),
    'Frist vorbei': ('Frist vorbei', 'Past due'),
    'Fälligkeiten mit Zählern, Halbjahr-Tabs und Schnitt.': ('Fälligkeiten mit Zählern, Halbjahr-Tabs und Schnitt.', 'Due dates with counters, semester tabs and average.'),
    'Für diese Woche sind keine Vertretungen eingetragen.': ('Für diese Woche sind keine Vertretungen eingetragen.', 'No substitutions scheduled for this week.'),
    'Für diesen Tag steht nichts im Plan.': ('Für diesen Tag steht nichts im Plan.', 'Nothing scheduled for this day.'),
    'Gefühlt': ('Gefühlt', 'Feels like'),
    'Geladene Datei teilen': ('Geladene Datei teilen', 'Share downloaded file'),
    'Gelöscht': ('Gelöscht', 'Deleted'),
    'Gerät (optional)': ('Gerät (optional)', 'Device (optional)'),
    'Geräte': ('Geräte', 'Devices'),
    'Geräte verwalten': ('Geräte verwalten', 'Manage devices'),
    'Gewichtung': ('Gewichtung', 'Weighting'),
    'Halbjahr': ('Halbjahr', 'Semester'),
    'Hallo!': ('Hallo!', 'Hello!'),
    'Hausaufgaben': ('Hausaufgaben', 'Homework'),
    'Hausaufgaben & Noten': ('Hausaufgaben & Noten', 'Homework & grades'),
    'Hell und Dunkel folgt dem System. Akzentfarbe:': ('Hell und Dunkel folgt dem System. Akzentfarbe:', 'Light and dark follow the system. Accent color:'),
    'Heute': ('Heute', 'Today'),
    'Hinzufügen': ('Hinzufügen', 'Add'),
    'In den Papierkorb': ('In den Papierkorb', 'Move to trash'),
    'Jetzt': ('Jetzt', 'Now'),
    'Kalender': ('Kalender', 'Calendar'),
    'Keine Hausaufgaben.': ('Keine Hausaufgaben.', 'No homework.'),
    'Keine Likes.': ('Keine Likes.', 'No likes.'),
    'Keine Nachrichten.': ('Keine Nachrichten.', 'No messages.'),
    'Keine Noten.': ('Keine Noten.', 'No grades.'),
    'Keine Schultermine oder Prüfungen in diesem Zeitraum.': ('Keine Schultermine oder Prüfungen in diesem Zeitraum.', 'No school events or exams in this period.'),
    'Keine neuen Nachrichten.': ('Keine neuen Nachrichten.', 'No new messages.'),
    'Keine offenen Hausaufgaben. Sehr gut.': ('Keine offenen Hausaufgaben. Sehr gut.', 'No open homework. Well done.'),
    'Keine weiteren Sitzungen.': ('Keine weiteren Sitzungen.', 'No other sessions.'),
    'Klasse Ø': ('Klasse Ø', 'Class Ø'),
    'Laden': ('Laden', 'Load'),
    'Lege fest, welche Bereiche zuerst erscheinen.': ('Lege fest, welche Bereiche zuerst erscheinen.', 'Choose which sections appear first.'),
    'Lernzeit': ('Lernzeit', 'Study time'),
    'Lokales Werkzeug — Zugangsdaten bleiben auf diesem Mac.': ('Lokales Werkzeug — Zugangsdaten bleiben auf diesem Mac.', 'Local tool — credentials stay on this Mac.'),
    'Luftdruck': ('Luftdruck', 'Pressure'),
    'Luftfeuchte': ('Luftfeuchte', 'Humidity'),
    'Lädt …': ('Lädt …', 'Loading …'),
    'Meldet dich ab und startet die Einführung erneut.': ('Meldet dich ab und startet die Einführung erneut.', 'Signs you out and restarts the introduction.'),
    'Mittwoch': ('Mittwoch', 'Wednesday'),
    'Montag': ('Montag', 'Monday'),
    'Morgen': ('Morgen', 'Tomorrow'),
    'Nach oben': ('Nach oben', 'Move up'),
    'Nach unten': ('Nach unten', 'Move down'),
    'Nachrichten': ('Nachrichten', 'Messages'),
    'Nachrichten & Threads': ('Nachrichten & Threads', 'Messages & threads'),
    'Neu laden': ('Neu laden', 'Reload'),
    'Neue Nachricht': ('Neue Nachricht', 'New message'),
    'Note': ('Note', 'Grade'),
    'Noten': ('Noten', 'Grades'),
    'Nur erledigte': ('Nur erledigte', 'Only done'),
    'Nur offene': ('Nur offene', 'Only open'),
    'Nur synthetische Beispieldaten vom lokalen Fake-Server': ('Nur synthetische Beispieldaten vom lokalen Fake-Server', 'Only synthetic sample data from the local fake server'),
    'Nur überfällige': ('Nur überfällige', 'Only overdue'),
    'Nächste 24 Stunden': ('Nächste 24 Stunden', 'Next 24 hours'),
    'Nächste →': ('Nächste →', 'Next →'),
    'Ohne erledigte': ('Ohne erledigte', 'Without done'),
    'Onboarding erneut durchlaufen': ('Onboarding erneut durchlaufen', 'Run onboarding again'),
    'Papierkorb': ('Papierkorb', 'Trash'),
    'Passwort': ('Passwort', 'Password'),
    'Passwort anzeigen': ('Passwort anzeigen', 'Show password'),
    'Passwort eingeben': ('Passwort eingeben', 'Enter password'),
    'Passwort verbergen': ('Passwort verbergen', 'Hide password'),
    'Prüfen …': ('Prüfen …', 'Checking …'),
    'Prüft …': ('Prüft …', 'Checking …'),
    'Schließen': ('Schließen', 'Close'),
    'Schulalltag': ('Schulalltag', 'School life'),
    'Schule': ('Schule', 'School'),
    'Schulfrei': ('Schulfrei', 'No school'),
    'Schulfrei.': ('Schulfrei.', 'No school.'),
    'Senden': ('Senden', 'Send'),
    'Sendet …': ('Sendet …', 'Sending …'),
    'Server-URL': ('Server-URL', 'Server URL'),
    'Sicht': ('Sicht', 'View'),
    'Sonnenaufgang': ('Sonnenaufgang', 'Sunrise'),
    'Sonnenuntergang': ('Sonnenuntergang', 'Sunset'),
    'Speichern': ('Speichern', 'Save'),
    'Speichern …': ('Speichern …', 'Saving …'),
    'Speichert …': ('Speichert …', 'Saving …'),
    'Standardfilter': ('Standardfilter', 'Default filter'),
    'Startseite nach Anmeldung': ('Startseite nach Anmeldung', 'Start page after sign-in'),
    'Stunden heute': ('Stunden heute', 'Classes today'),
    'Stundenplan': ('Stundenplan', 'Timetable'),
    'Suche': ('Suche', 'Search'),
    'Suchen': ('Suchen', 'Search'),
    'Tag': ('Tag', 'Day'),
    'Termine': ('Termine', 'Events'),
    'Termine und Planänderungen': ('Termine und Planänderungen', 'Events and schedule changes'),
    'Tests einbeziehen': ('Tests einbeziehen', 'Include tests'),
    'Tests und Prüfungen einbeziehen': ('Tests und Prüfungen einbeziehen', 'Include tests and exams'),
    'Thema': ('Thema', 'Topic'),
    'Titel': ('Titel', 'Title'),
    'Trage ein, wo EduFlow als Server läuft.': ('Trage ein, wo EduFlow als Server läuft.', 'Enter where EduFlow runs as server.'),
    'Typ': ('Typ', 'Type'),
    'Unbekanntes Gerät': ('Unbekanntes Gerät', 'Unknown device'),
    'Und dein Passwort?': ('Und dein Passwort?', 'And your password?'),
    'Veranstaltung': ('Veranstaltung', 'Event'),
    'Verbindung testen': ('Verbindung testen', 'Test connection'),
    'Verbunden': ('Verbunden', 'Connected'),
    'Vertretungen': ('Vertretungen', 'Substitutions'),
    'Weiter': ('Weiter', 'Continue'),
    'Weiter ›': ('Weiter ›', 'Continue ›'),
    'Welches Gerät meldest du an?': ('Welches Gerät meldest du an?', 'Which device are you signing in?'),
    'Wetter': ('Wetter', 'Weather'),
    'Wetter: Stadt (optional)': ('Wetter: Stadt (optional)', 'Weather: city (optional)'),
    'Wetterkarte anzeigen': ('Wetterkarte anzeigen', 'Show weather map'),
    'Wie heißt du bei EduPage?': ('Wie heißt du bei EduPage?', 'What is your EduPage username?'),
    'Wieder öffnen': ('Wieder öffnen', 'Reopen'),
    'Wo läuft dein Server?': ('Wo läuft dein Server?', 'Where does your server run?'),
    'Woche': ('Woche', 'Week'),
    'Wolken': ('Wolken', 'Clouds'),
    'Zurück': ('Zurück', 'Back'),
    'Zurück zur Anmeldung': ('Zurück zur Anmeldung', 'Back to sign-in'),
    'Zurückholen': ('Zurückholen', 'Restore'),
    'Zurückholen (als offen)': ('Zurückholen (als offen)', 'Restore (as open)'),
    'Zusatz': ('Zusatz', 'Extra'),
    'Zwischengespeichert': ('Zwischengespeichert', 'Cached'),
    'auth_hint_device': ('Welches Gerät meldest du an?', 'Which device are you signing in?'),
    'auth_hint_password': ('Und dein Passwort?', 'And your password?'),
    'auth_hint_server': ('Wo läuft dein Server?', 'Where does your server run?'),
    'auth_hint_subdomain': ('Leer lassen für automatische Erkennung.', 'Leave empty for automatic detection.'),
    'auth_hint_username': ('Wie heißt du bei EduPage?', 'What is your EduPage username?'),
    'auth_label_device': ('Gerät (optional)', 'Device (optional)'),
    'auth_label_password': ('Passwort', 'Password'),
    'auth_label_server': ('Server-URL', 'Server URL'),
    'auth_label_subdomain': ('Subdomain (optional)', 'School domain (optional)'),
    'auth_label_username': ('Benutzername', 'User name'),
    'auth_nav_2fa': ('Zwei-Faktor-Code', 'Two-factor code'),
    'auth_nav_login': ('Anmelden', 'Sign in'),
    'auth_placeholder_code': ('6-stelliger Code', '6-digit code'),
    'auth_placeholder_device': ('z. B. MacBook', 'e.g. MacBook'),
    'auth_placeholder_password': ('Passwort eingeben', 'Enter password'),
    'auth_placeholder_subdomain': ('z. B. musterschule', 'e.g. my-school'),
    'z. B. musterschule': ('z. B. musterschule', 'e.g. myschool'),
    'auth_placeholder_username': ('z. B. max.muster', 'e.g. max.muster'),
    'auth_step_counter': ('Schritt %d von %d', 'Step %d of %d'),
    'common_accent_black': ('Schwarz', 'Black'),
    'common_accent_blue': ('Blau', 'Blue'),
    'common_accent_green': ('Grün', 'Green'),
    'common_accent_red': ('Rot', 'Red'),
    'common_accent_teal': ('Petrol', 'Teal'),
    'common_accent_violet': ('Violett', 'Violet'),
    'common_clear_input': ('Eingabe löschen', 'Clear input'),
    'common_error_bad_credentials': ('Falscher Benutzername, Passwort oder Subdomain.', 'Wrong username, password or subdomain.'),
    'common_error_captcha_required': ('EduPage verlangt ein Captcha. Bitte einmal im Browser anmelden.', 'EduPage requires a captcha. Please sign in via browser once.'),
    'common_error_config_missing': ('Server-Schlüssel fehlt. Bitte später erneut versuchen.', 'Server key missing. Please try again later.'),
    'common_error_edupage_2fa': ('EduPage verlangt erneut einen Code. Bitte neu anmelden.', 'EduPage requires a code again. Please sign in again.'),
    'common_error_invalid_code': ('Der Code wurde nicht akzeptiert. Bitte erneut versuchen.', 'The code was not accepted. Please try again.'),
    'common_error_not_found': ('Nicht gefunden.', 'Not found.'),
    'common_error_pending_invalid': ('Zwischenschritt abgelaufen. Bitte erneut anmelden.', 'Intermediate step expired. Please sign in again.'),
    'common_error_rate_limited': ('Zu viele Versuche. Bitte später erneut versuchen.', 'Too many attempts. Please try again later.'),
    'common_error_token_expired': ('Sitzung abgelaufen. Bitte erneut anmelden.', 'Session expired. Please sign in again.'),
    'common_error_token_invalid': ('Sitzung ungültig. Bitte erneut anmelden.', 'Session invalid. Please sign in again.'),
    'common_error_upstream': ('Anfrage fehlgeschlagen. Bitte später erneut versuchen.', 'Request failed. Please try again later.'),
    'common_error_validation': ('Ungültige Eingabe. Bitte prüfen und erneut versuchen.', 'Invalid input. Please check and try again.'),
    'common_loading': ('Lädt …', 'Loading …'),
    'common_password_hide': ('Passwort verbergen', 'Hide password'),
    'common_password_show': ('Passwort anzeigen', 'Show password'),
    'common_profile_menu_open': ('Profilmenü öffnen', 'Open profile menu'),
    'common_toggle_off': ('Aus', 'Off'),
    'common_toggle_on': ('Ein', 'On'),
    'common_unknown_author': ('(unbekannt)', '(unknown)'),
    'content_demo_hint': ('Nur synthetische Beispieldaten vom lokalen Fake-Server', 'Only synthetic sample data from the local fake server'),
    'devices_count': ('%d Sitzungen', '%d sessions'),
    'devices_valid_until': ('Gültig bis %@', 'Valid until %@'),
    'erledigt': ('erledigt', 'completed'),
    'grades_average_hint': ('Schnitt aus klassischen Noten, nach Gewichtung.', 'Average of classic grades, weighted.'),
    'grades_average_stats': ('Schnitt: %@', 'Average: %@'),
    'grades_halfyear_all': ('Gesamt', 'All'),
    'grades_halfyear_format': ('%d. Halbjahr %d/%@', 'Semester %d (%d/%@)'),
    'grades_load_more': ('Mehr laden (%d/%d)', 'Load more (%d/%d)'),
    'grades_nav': ('Noten', 'Grades'),
    'grades_not_classic': ('o. Wertung', 'not graded'),
    'grades_picker_halfyear': ('Halbjahr', 'Semester'),
    'grades_search_placeholder': ('Suchen', 'Search'),
    'grades_subject_average_caption': ('Fachschn. gewichtet', 'Subject avg. weighted'),
    'grades_subject_count': ('%d Noten', '%d grades'),
    'grades_subject_other': ('Sonstiges', 'Other'),
    'grades_summary_stats': ('%d Noten · %d Fächer · Schnitt: %@', '%d grades · %d subjects · average: %@'),
    'grades_weight_format': ('Gewichtung %@', 'Weighting %@'),
    'grades_weight_once': ('Gewichtung ×1', 'Weighting ×1'),
    'homework_action_done': ('Fertig', 'Done'),
    'homework_action_reopen': ('Wieder öffnen', 'Reopen'),
    'homework_action_restore': ('Zurückholen', 'Restore'),
    'homework_action_trash': ('Papierkorb', 'Trash'),
    'homework_count': ('%d Aufgaben', '%d homework'),
    'homework_deleted': ('Gelöscht', 'Deleted'),
    'homework_due_prefix': ('fällig: ', 'due: '),
    'homework_empty_all': ('Keine Hausaufgaben.', 'No homework.'),
    'homework_empty_done': ('Noch nichts erledigt.', 'Nothing completed yet.'),
    'homework_empty_open': ('Keine offenen Aufgaben.', 'No open tasks.'),
    'homework_empty_overdue': ('Nichts überfällig.', 'Nothing overdue.'),
    'homework_empty_trash': ('Der Papierkorb ist leer.', 'The trash is empty.'),
    'homework_filter_all': ('Alle', 'All'),
    'homework_filter_done': ('Erledigt', 'Completed'),
    'homework_filter_open': ('Offen', 'Open'),
    'homework_filter_overdue': ('Überfällig', 'Overdue'),
    'homework_filter_trash': ('Papierkorb', 'Recycle bin'),
    'homework_load_more': ('Mehr laden (%d/%d)', 'Load more (%d/%d)'),
    'homework_menu_done': ('Als erledigt markieren', 'Mark as done'),
    'homework_menu_restore': ('Zurückholen (als offen)', 'Restore (as open)'),
    'homework_menu_trash': ('In den Papierkorb', 'Move to trash'),
    'homework_nav': ('Hausaufgaben', 'Homework'),
    'homework_no_description': ('(keine Beschreibung)', '(no description)'),
    'homework_search_placeholder': ('Suchen', 'Search'),
    'homework_toggle_tests': ('Tests einbeziehen', 'Include tests'),
    'kein Unterricht heute': ('kein Unterricht heute', 'no classes today'),
    'messages_action_mark_read': ('Alle als gelesen', 'Mark all as read'),
    'messages_action_reload': ('Neu laden', 'Reload'),
    'messages_attachment_load': ('Anhang laden', 'Load attachment'),
    'messages_compose_search_placeholder': ('Suche', 'Search'),
    'messages_count': ('%d Nachrichten', '%d messages'),
    'messages_empty': ('Keine Nachrichten.', 'No messages.'),
    'messages_file_fallback': ('Datei %d', 'File %d'),
    'messages_load_more': ('Mehr laden (%d/%d)', 'Load more (%d/%d)'),
    'messages_marked_read': ('%d als gelesen markiert.', '%d marked as read.'),
    'messages_nav_compose': ('Neue Nachricht', 'New message'),
    'messages_nav_list': ('Nachrichten', 'Messages'),
    'messages_picker_type': ('Typ', 'Type'),
    'messages_recipients_chosen': ('Empfänger (%d gewählt)', 'Recipients (%d selected)'),
    'messages_replies_count': ('Antworten (%d)', 'Replies (%d)'),
    'messages_search_placeholder': ('Suchen', 'Search'),
    'messages_state_read': ('Gelesen', 'Read'),
    'messages_state_unread': ('Ungelesen', 'Unread'),
    'messages_type_anketa': ('Umfrage', 'Poll'),
    'messages_type_genotif': ('Mitteilung', 'Notification'),
    'messages_type_news': ('Neuigkeit', 'News'),
    'messages_type_sprava': ('Nachricht', 'Message'),
    'messages_unread': ('Neu', 'New'),
    'messages_unread_count': ('%d ungelesen', '%d unread'),
    'offen': ('offen', 'open'),
    'ohne Datum': ('ohne Datum', 'No date'),
    'onboarding_feature_homework_text': ('Fälligkeiten mit Zählern, Halbjahr-Tabs und Schnitt.', 'Due dates with counters, semester tabs and average.'),
    'onboarding_feature_homework_title': ('Hausaufgaben & Noten', 'Homework & Grades'),
    'onboarding_feature_messages_text': ('Alle EduPage-Nachrichten im Mail-Layout — mit Likes, Antworten und Dateien.', 'All EduPage messages in a mail layout — with likes, replies and files.'),
    'onboarding_feature_messages_title': ('Nachrichten & Threads', 'Messages & Threads'),
    'onboarding_feature_timetable_text': ('Tag und Woche und Wetter auf der Übersicht.', 'Day and week plus weather on the overview.'),
    'onboarding_feature_timetable_title': ('Stundenplan & Wetter', 'Timetable & Weather'),
    'onboarding_greeting': ('Merhaba!', 'Hello!'),
    'onboarding_language_subtitle': ('EduFlow spricht deine Sprache. Die Auswahl wird sofort übernommen.', 'EduFlow speaks your language. The choice applies immediately.'),
    'overview_city_missing': ('Bitte eine Stadt in den Einstellungen eintragen.', 'Please enter a city in settings.'),
    'overview_homework_all_done': ('Alle Hausaufgaben erledigt. Sehr gut.', 'All homework done. Well done.'),
    'overview_homework_more_available': ('Weitere Aufgaben vorhanden — alle ansehen.', 'More tasks available — view all.'),
    'overview_homework_none': ('Keine Hausaufgaben vorhanden.', 'No homework available.'),
    'overview_homework_sub': ('%d offen · %d überfällig', '%d open · %d overdue'),
    'overview_lesson_detail': ('%@. Std · %@%@%@', '%@. period · %@%@%@'),
    'overview_lesson_room': (' · Raum %@', ' · Room %@'),
    'overview_messages_empty': ('Keine neuen Nachrichten.', 'No new messages.'),
    'overview_messages_total': ('Nachrichten · %d', 'Messages · %d'),
    'overview_more_homework': ('+ %d weitere', '+ %d more'),
    'overview_more_messages': ('+ %d weitere', '+ %d more'),
    'overview_nav': ('Übersicht', 'Overview'),
    'overview_weather_in_city': ('Wetter in %@', 'Weather in %@'),
    'overview_week_label': ('%@ haftası', 'Week %@'),
    'school_action_add': ('NEU', 'NEW'),
    'school_action_changed': ('GEÄNDERT', 'CHANGED'),
    'school_action_remove': ('ENTFÄLLT', 'CANCELLED'),
    'school_class_format': ('Klasse %@', 'Class %@'),
    'school_kind_attendance': ('ANWESENHEIT', 'ATTENDANCE'),
    'school_kind_event': ('SCHULTERMIN', 'SCHOOL EVENT'),
    'school_kind_exam': ('TEST / PRÜFUNG', 'TEST / EXAM'),
    'school_nav': ('Termine & Vertretungen', 'Events & substitutions'),
    'school_picker_section': ('Bereich', 'Section'),
    'school_plan_change': ('Stundenplanänderung', 'Timetable change'),
    'school_tab_agenda': ('Kalender', 'Calendar'),
    'school_tab_substitutions': ('Vertretungen', 'Substitutions'),
    'school_week_from': ('Woche ab %@', 'Week of %@'),
    'settings_baseurl_placeholder': ('Basis-URL', 'Base URL'),
    'settings_cache_clear': ('Cache leeren', 'Clear cache'),
    'settings_cache_clear_busy': ('Cache leeren …', 'Clearing cache …'),
    'settings_cache_cleared': ('Cache geleert (%d Dateien).', 'Cache cleared (%d files).'),
    'settings_devices_nav': ('Geräte', 'Devices'),
    'settings_filter_all_desc': ('Alles zeigen', 'Show everything'),
    'settings_filter_all_title': ('Alle', 'All'),
    'settings_filter_done_desc': ('Fertige Aufgaben', 'Completed tasks'),
    'settings_filter_done_title': ('Nur erledigte', 'Only completed'),
    'settings_filter_open_desc': ('Ohne erledigte', 'Without done'),
    'settings_filter_open_title': ('Nur offene', 'Only open'),
    'settings_filter_overdue_desc': ('Frist vorbei', 'Past due'),
    'settings_filter_overdue_title': ('Nur überfällige', 'Only past due'),
    'settings_filter_trash_desc': ('Ausgeblendete', 'Hidden'),
    'settings_filter_trash_title': ('Papierkorb', 'Recycle bin'),
    'settings_landing_grades_desc': ('Direkt zu den Noten', 'Go straight to grades'),
    'settings_landing_grades_title': ('Noten', 'Notes'),
    'settings_landing_homework_desc': ('Direkt zu den Aufgaben', 'Go straight to homework'),
    'settings_landing_homework_title': ('Hausaufgaben', 'Homework'),
    'settings_landing_messages_desc': ('Direkt in die Nachrichten', 'Go straight to messages'),
    'settings_landing_messages_title': ('Nachrichten', 'News'),
    'settings_landing_overview_desc': ('Uhr, Nachrichten, Wetter', 'Clock, messages, weather'),
    'settings_landing_overview_title': ('Übersicht', 'Summary'),
    'settings_landing_timetable_desc': ('Direkt zum Stundenplan', 'Go straight to timetable'),
    'settings_landing_timetable_title': ('Stundenplan', 'Timetable'),
    'settings_max_homework': ('Max. offene Hausaufgaben: %d', 'Max. open homework: %d'),
    'settings_max_unread': ('Max. ungelesene Nachrichten: %d', 'Max. unread messages: %d'),
    'settings_nav': ('Einstellungen', 'Settings'),
    'settings_navbar_available': ('Verfügbar', 'Available'),
    'settings_navbar_desc': ('Lege fest, welche Bereiche oben erscheinen und in welcher Reihenfolge. Termine bleiben auch ohne Reiter über das Profilmenü erreichbar.', 'Choose which sections appear on top and in which order. Events stay reachable via the profile menu even without a tab.'),
    'settings_navbar_title': ('Navigationsleiste', 'Navigation bar'),
    'settings_ov_order_hint': ('Wird mit „Speichern“ übernommen.', 'Applied when you save.'),
    'settings_ov_order_title': ('Reihenfolge der Bereiche', 'Section order'),
    'settings_toggle_dev_options': ('Entwickleroptionen aktivieren', 'Enable developer options'),
    'settings_toggle_hw_tests': ('Tests und Prüfungen einbeziehen', 'Include tests and exams'),
    'settings_toggle_onboarding_restart': ('Onboarding erneut durchlaufen', 'Run onboarding again'),
    'settings_toggle_wetter_map': ('Wetterkarte anzeigen', 'Show weather map'),
    'settings_wetter_city_placeholder': ('Wetter: Stadt (optional)', 'Weather: city (optional)'),
    'timetable_nav': ('Stundenplan', 'Timetable'),
    'timetable_room': ('Raum %@', 'Room %@'),
    'z. B. MacBook': ('z. B. MacBook', 'e.g. MacBook'),
    'z. B. max.muster': ('z. B. max.muster', 'e.g. max.muster'),
    'Übermorgen': ('Übermorgen', 'Day after tomorrow'),
    'Übernehmen': ('Übernehmen', 'Apply'),
    'Übernehmen & weiter': ('Übernehmen & weiter', 'Apply & continue'),
    'Übersicht': ('Übersicht', 'Overview'),
    'Übersicht anpassen': ('Übersicht anpassen', 'Customize overview'),
    'überfällig': ('überfällig', 'overdue'),
    '‹ Zurück': ('‹ Zurück', '‹ Back'),
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
