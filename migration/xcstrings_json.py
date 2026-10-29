"""Serialisiert `Localizable.xcstrings` im Stil von Xcode.

Xcode schreibt `"key" : "value"` (Leerzeichen vor dem Doppelpunkt) und
leere Objekte als zwei Zeilen:

    "%@ %%" : {

    },

`json.dumps(indent=2)` liefert stattdessen `"key": "value"` und `{}` in
einer Zeile. Beim Reparieren des Katalogs wuerde das jede Zeile der Datei
aendern und den Diff unbrauchbar machen. Dieses Modul erhaelt den Stil,
sodass ein Fix nur die tatsaechlich geaenderten Werte zeigt.

    python3 -c "import sys; sys.path.insert(0,'migration'); import xcstrings_json"
"""
import json


def dumps(daten):
    # Ohne abschliessenden Zeilenumbruch: so schreibt Xcode die Datei, und
    # ein angehaengter Newline wuerde die letzte Zeile des Diffs veraendern.
    return _wert(daten, 0)


def _wert(wert, tiefe):
    einruecken = "  " * tiefe
    innen = "  " * (tiefe + 1)
    if isinstance(wert, dict):
        if not wert:
            # Xcode haelt leere Objekte offen, nicht als `{}`.
            return "{\n\n" + einruecken + "}"
        zeilen = []
        for schluessel, teil in wert.items():
            zeilen.append(
                innen
                + json.dumps(schluessel, ensure_ascii=False)
                + " : "
                + _wert(teil, tiefe + 1)
            )
        return "{\n" + ",\n".join(zeilen) + "\n" + einruecken + "}"
    if isinstance(wert, list):
        if not wert:
            return "[\n\n" + einruecken + "]"
        zeilen = [innen + _wert(teil, tiefe + 1) for teil in wert]
        return "[\n" + ",\n".join(zeilen) + "\n" + einruecken + "]"
    return json.dumps(wert, ensure_ascii=False)


def load(pfad):
    with open(pfad, encoding="utf-8") as datei:
        return json.load(datei)
