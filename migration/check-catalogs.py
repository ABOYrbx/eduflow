"""Findet deutsche Reste in den übersetzten Katalogen.

Nach einem Crowdin-Sync landen in noch nicht übersetzten Sprachen deutsche
Ausgangstexte statt englischer — die Oberfläche sieht dann nach einem
halb übersetzten deutschen Interface aus. Dieses Skript findet solche Werte
und kann sie durch den englischen Quelltext ersetzen.

    python3 migration/check-catalogs.py            # nur melden
    python3 migration/check-catalogs.py --fix      # durch Englisch ersetzen

Zwei Regeln, bewusst konservativ:

1. Der normalisierte Wert (ohne Satzzeichen, kleingeschrieben) entspricht dem
   deutschen Wert, während sich der englische unterscheidet. Fängt
   Ablehnungen wie 'Schul-Subdomain' zu 'Schulsubdomain'. Nur für Sprachen
   mit geringer Abdeckung — bei guten Übersetzungen kann ein Wert zufällig
   dem deutschen gleichen ('Datum:' ist im Niederländischen richtig).
2. Mindestens 60 % der Wörter (ab 4 Zeichen) kommen nur im Deutschen vor.
   Bei Einwort-Werten genügt ein eindeutig deutsches Wort.

Was beide Regeln nicht fassen, ist eine kurze Entscheidung von Hand wert —
im September 2026 war das ein einzelnes 'Gültig bis {date}.' im Chinesischen.
"""
import glob
import json
import os
import re
import sys

BASIS = ["apps/web/messages", "apps/api/src/messages"]

# Wortformen, die in anderen Sprachen genauso vorkommen (Kognite) und
# deshalb nicht als deutsches Indiz gelten.
KOGNITE = {
    "token", "kalender", "titel", "datum", "profil", "alle", "morgen",
    "lektion", "note", "liste", "faktor", "ller", "modus", "lokale",
    "konto", "licht",
}

WORT = re.compile(r"[A-Za-zÄÖÜäöüß]{4,}")
NORMAL = re.compile(r"[^a-zäöüß]")

# Ab dieser Zahl echter Übersetzungen gilt eine Sprache als gut übersetzt.
ABDECKUNG_GUT = 200


def flatten(node, prefix="", out=None):
    out = {} if out is None else out
    if isinstance(node, dict):
        for key, value in node.items():
            flatten(value, f"{prefix}{key}.", out)
    else:
        out[prefix[:-1]] = node
    return out


def normalisiert(text):
    return NORMAL.sub("", text.lower())


def stil_von(quelle, daten):
    for kwargs, ende in [
        ({"ensure_ascii": True, "indent": 2}, "\n"),
        ({"ensure_ascii": False, "indent": 2}, "\n"),
        ({"ensure_ascii": True, "indent": 2}, ""),
        ({"ensure_ascii": False, "indent": 2}, ""),
        ({"ensure_ascii": True, "indent": 4}, "\n"),
        ({"ensure_ascii": False, "indent": 4}, "\n"),
        ({"ensure_ascii": True, "separators": (",", ":")}, ""),
        ({"ensure_ascii": False, "separators": (",", ":")}, ""),
    ]:
        if json.dumps(daten, **kwargs) + ende == quelle:
            return kwargs, ende
    raise ValueError("Dateistil unbekannt")


def ist_deutsch(wert, deutsch, englisch, deutsch_woerter, auch_gleich):
    if not isinstance(wert, str) or wert == englisch:
        return False
    if (auch_gleich and isinstance(deutsch, str) and isinstance(englisch, str)
            and normalisiert(deutsch) != normalisiert(englisch)
            and normalisiert(wert) == normalisiert(deutsch)):
        return True
    woerter = [w.lower() for w in WORT.findall(wert)]
    if not woerter:
        return False
    treffer = [w for w in woerter if w in deutsch_woerter and w not in KOGNITE]
    if len(woerter) == 1:
        return len(treffer) == 1
    return len(treffer) / len(woerter) >= 0.6


def main():
    reparieren = "--fix" in sys.argv
    gesamt = 0
    for wurzel in BASIS:
        if not os.path.isdir(wurzel):
            continue
        en = flatten(json.load(open(f"{wurzel}/en.json", encoding="utf-8")))
        de = flatten(json.load(open(f"{wurzel}/de.json", encoding="utf-8")))
        deutsch_woerter = set()
        for key, wert in de.items():
            quelle = en.get(key, "")
            if isinstance(wert, str) and isinstance(quelle, str):
                deutsch_woerter |= set(w.lower() for w in WORT.findall(wert))
                deutsch_woerter -= set(w.lower() for w in WORT.findall(quelle))
        for pfad in sorted(glob.glob(f"{wurzel}/*.json")):
            sprache = os.path.basename(pfad)[:-5]
            if sprache in ("en", "de"):
                continue
            roh = open(pfad, encoding="utf-8").read()
            daten = json.loads(roh)
            kwargs, ende = stil_von(roh, daten)
            flach = flatten(daten)
            echt = sum(1 for k in flach if k in en and flach[k] != en[k] and flach[k] != de.get(k))
            gering = echt < ABDECKUNG_GUT
            treffer = {
                k: v for k, v in flach.items()
                if ist_deutsch(v, de.get(k), en.get(k), deutsch_woerter, gering)
            }
            if not treffer:
                continue
            gesamt += len(treffer)
            print(f"{os.path.basename(pfad):10} {len(treffer):>4} deutsche Reste ({echt} echte Uebersetzungen)")
            for key in sorted(treffer)[:4]:
                print(f"           {key}: {treffer[key]!r}")
            if not reparieren:
                continue
            neu = dict(flach)
            for key in treffer:
                neu[key] = en[key]
            frisch = {}
            for key, wert in neu.items():
                teile = key.split(".")
                knoten = frisch
                for teil in teile[:-1]:
                    knoten = knoten.setdefault(teil, {})
                knoten[teile[-1]] = wert
            ausgabe = json.dumps(frisch, **kwargs) + ende
            assert json.loads(ausgabe) == frisch
            open(pfad, "w", encoding="utf-8").write(ausgabe)
    print(f'{"gefunden" if not reparieren else "ersetzt"}: {gesamt}')
    return 1 if gesamt and not reparieren else 0


if __name__ == "__main__":
    sys.exit(main())
