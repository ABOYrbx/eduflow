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
    "hu": {"Kalender", "Dátum"},
}

NORMAL = re.compile(r"[^a-zäöüß]")


def norm(text):
    # NFC zuerst: der deutsche Katalog mischt zerlegte Umlaute (A + U+0308)
    # und zusammengesetzte (Ä). Ohne das gelten 'ENTFÄLLT' und 'ENTFÄLLT'
    # als verschieden.
    return NORMAL.sub("", unicodedata.normalize("NFC", text or "").lower())


def wert(eintrag, sprache):
    teil = eintrag.get("localizations", {}).get(sprache)
    return teil.get("stringUnit", {}).get("value") if teil else None


def setze(eintrag, sprache, neuer):
    eintrag["localizations"][sprache]["stringUnit"]["value"] = neuer


def main():
    reparieren = "--fix" in sys.argv
    with open(PFAD, encoding="utf-8") as datei:
        daten = json.load(datei)
    strings = daten["strings"]
    sprachen = sorted({sp for e in strings.values() for sp in e.get("localizations", {})})

    # 1) Englische Lokalisierung reparieren
    for eintrag in strings.values():
        alt = wert(eintrag, "en")
        if alt in ENGLISCH:
            neuer = ENGLISCH[alt]
            print(f"  en: {alt!r} -> {neuer!r}")
            if reparieren:
                setze(eintrag, "en", neuer)

    # 2) Deutsche Werte in anderen Sprachen durch Englisch ersetzen
    pro_sprache = {}
    for key, eintrag in strings.items():
        neu_en = wert(eintrag, "en")
        deutsch = wert(eintrag, "de")
        if neu_en is None or deutsch is None:
            continue
        for sprache in sprachen:
            if sprache in ("de", "en"):
                continue
            alt = wert(eintrag, sprache)
            if alt is None or alt == neu_en:
                continue
            if norm(alt) != norm(deutsch) or norm(deutsch) == norm(neu_en):
                continue
            if alt in KOGNITE.get(sprache, set()):
                continue
            pro_sprache[sprache] = pro_sprache.get(sprache, 0) + 1
            if reparieren:
                setze(eintrag, sprache, neu_en)

    for sprache, anzahl in sorted(pro_sprache.items(), key=lambda pa: -pa[1]):
        print(f"  {sprache:8} {anzahl:>4} deutsche Werte -> Englisch")

    if reparieren:
        with open(PFAD, "w", encoding="utf-8") as datei:
            json.dump(daten, datei, ensure_ascii=False, indent=2)
            datei.write("\n")
        print("Katalog geschrieben")
    else:
        print(f'{"gefunden" if not reparieren else "ersetzt"}: {sum(pro_sprache.values())}')
    return 0


if __name__ == "__main__":
    sys.exit(main())
