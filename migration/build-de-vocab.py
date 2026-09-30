"""Baut migration/de-vokabular.json: alle deutschen Wortformen im Projekt.

Der Katalog `de.json` allein reicht als Wortschatz nicht. Die deutschen Reste
in den uebersetzten Katalogen stammen aus einer aelteren deutschen Fassung der
Oberflaeche ("Vertretungsplan", waehrend `de.json` inzwischen "Ersetzungsplan"
sagt), und genau diese Worte kommen in keiner aktuellen Datei mehr vor. Ohne
sie meldet die Pruefung nichts und das Interface zeigt weiter Deutsch.

Deshalb wird der Wortschatz aus drei Quellen zusammengestellt:

1. allen Revisionen der deutschen Kataloge in der Git-Historie,
2. den deutschen Werten von Web und Backend heute,
3. den deutschen Quelltexten der nativen Apps (Android `values-de`, macOS
   Schluessel und `de`-Lokalisierungen).

Abgezogen wird, was auch Englisch ist - Markennamen wie `EduFlow` und
Fachwoerter wie `Token` wuerden sonst jede Sprache treffen.

    python3 migration/build-de-vocab.py            # neu erzeugen
    python3 migration/build-de-vocab.py --show     # nur ansehen
"""
import glob
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ZIEL = "migration/de-vokabular.json"
WORT = re.compile(r"[A-Za-zÄÖÜäöüß]{4,}")
KATALOGE = ["apps/web/messages", "apps/api/src/messages"]


def sammel(text, woerter):
    if not isinstance(text, str):
        return
    for wort in WORT.findall(text):
        woerter.add(wort.lower())


def sammel_knoten(node, woerter):
    if isinstance(node, dict):
        for wert in node.values():
            sammel_knoten(wert, woerter)
    else:
        sammel(node, woerter)


def aus_git(verzeichnis, woerter):
    """Alle jemals geschriebenen Fassungen des deutschen Katalogs."""
    pfade = subprocess.run(
        ["git", "log", "--format=%H", "--", f"{verzeichnis}/de.json"],
        capture_output=True, text=True).stdout.split()
    ausgewertet = 0
    for revision in pfade:
        roh = subprocess.run(
            ["git", "show", f"{revision}:{verzeichnis}/de.json"],
            capture_output=True, text=True).stdout
        if not roh:
            continue
        try:
            sammel_knoten(json.loads(roh), woerter)
            ausgewertet += 1
        except json.JSONDecodeError:
            continue  # alter Dateistil, kein gueltiges JSON
    return ausgewertet, len(pfade)


def main():
    nur_ansehen = "--show" in sys.argv
    deutsch = set()
    bericht = []

    for verzeichnis in KATALOGE:
        if not os.path.isdir(verzeichnis):
            continue
        ausgewertet, gesamt = aus_git(verzeichnis, deutsch)
        bericht.append(f"  {verzeichnis}/de.json: {ausgewertet} von {gesamt} Revisionen")
        pfad = f"{verzeichnis}/de.json"
        if os.path.isfile(pfad):
            sammel_knoten(json.load(open(pfad, encoding="utf-8")), deutsch)

    for pfad in glob.glob("android/**/values-de/strings.xml", recursive=True):
        for knoten in ET.parse(pfad).getroot().findall("string"):
            sammel(knoten.text or "", deutsch)
        bericht.append(f"  {pfad}")

    for pfad in glob.glob("mac/**/Localizable.xcstrings", recursive=True):
        datei = json.load(open(pfad, encoding="utf-8"))
        for schluessel, eintrag in datei.get("strings", {}).items():
            sammel(schluessel, deutsch)  # Schluessel sind deutscher Klartext
            for sprache in ("de", "de-DE"):
                ziel = eintrag.get("localizations", {}).get(sprache)
                if ziel:
                    sammel(ziel.get("stringUnit", {}).get("value", ""), deutsch)
        bericht.append(f"  {pfad}")

    # Alles abziehen, was im Englischen steht: das sind gemeinsame Woerter
    # und keine deutschen Indizien.
    for verzeichnis in KATALOGE:
        pfad = f"{verzeichnis}/en.json"
        if not os.path.isfile(pfad):
            continue
        englisch = set()
        sammel_knoten(json.load(open(pfad, encoding="utf-8")), englisch)
        deutsch -= englisch

    bericht.append(f"  gemeinsam mit Englisch abgezogen: {len(englisch)}")
    print("\n".join(bericht))
    print(f"deutscher Wortschatz: {len(deutsch)} Woerter")

    if nur_ansehen:
        probe = ["vertretungsplan", "aufgaben", "darstellung", "pfeilen", "anpassen", "stunden"]
        print("  Proben:", {w: (w in deutsch) for w in probe})
        return 0

    alt = os.path.exists(ZIEL)
    json.dump(sorted(deutsch), open(ZIEL, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    print(("aktualisiert: " if alt else "geschrieben: ") + ZIEL)
    return 0


if __name__ == "__main__":
    sys.exit(main())
