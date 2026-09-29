#!/usr/bin/env python3
"""Berechnet den Übersetzungsstand je Sprache und schreibt die Coverage-Tabelle
in `ui/auth/AppLocale.kt`.

Ohne diesen Schritt zeigt die Sprachauswahl im Onboarding für alle Sprachen
außer Deutsch/Englisch 0 %, weil die Tabelle dort historisch fest verdrahtet war.

Aufruf (aus `android/`):
    python3 tools/update_locale_coverage.py [--check]

`--check` ändert nichts, sondern meldet nur, ob die Tabelle in AppLocale.kt noch
zum Stand der Sprachdateien passt (für CI).
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

RES = os.path.join("app", "src", "main", "res")
SOURCE = os.path.join(RES, "values", "strings.xml")
TARGET = os.path.join("app", "src", "main", "java", "de", "eduflow", "android",
                      "ui", "auth", "AppLocale.kt")

# Quellsprache der Lokalisierung: nicht übersetzt, gilt immer als vollständig.
SOURCE_LOCALE = "en"

# `translatable="false"` wird nie übersetzt und zählt nicht in die Quote.
NOT_TRANSLATABLE = re.compile(r'translatable\s*=\s*"false"')


def normalize(text: str) -> str:
    """XML-Entities auflösen, Leerraum vereinheitlichen.

    Ohne das zählen reine Einrückungs- oder Zeilenumbruch-Unterschiede als
    Übersetzung — der Kotlin-Test in `OnboardingLocaleTest` rechnet genauso.
    """
    text = (text.replace("&lt;", "<").replace("&gt;", ">")
                .replace("&quot;", '"').replace("&apos;", "'")
                .replace("&amp;", "&"))
    return " ".join(text.split())


def read_strings(path: str) -> dict[str, str]:
    """Name -> Text. Nicht übersetzbare Einträge fallen raus."""
    out: dict[str, str] = {}
    for element in ET.parse(path).getroot():
        if element.tag not in ("string", "string-array", "plurals"):
            continue
        if NOT_TRANSLATABLE.search(ET.tostring(element, encoding="unicode")):
            continue
        out[element.get("name", "")] = normalize("".join(element.itertext()))
    return out


def variant_code(qualifier: str) -> str:
    """`values-de-rDE` -> `de`, `values-pt-rBR` -> `pt`."""
    return qualifier.removeprefix("values-").split("-")[0].lower()


def collect() -> dict[str, tuple[int, int]]:
    """code -> (übersetzt, gesamt).

    Varianten derselben Sprache (`de` + `de-rDE`) werden vereinigt: ein Key
    zählt als übersetzt, sobald ihn mindestens eine Variante übersetzt hat.
    """
    source = read_strings(SOURCE)
    total = len(source)
    if total == 0:
        sys.exit(f"FEHLER: keine Strings in {SOURCE}")

    translated: dict[str, set[str]] = {}
    for path in sorted(glob.glob(os.path.join(RES, "values-*", "strings.xml"))):
        qualifier = os.path.basename(os.path.dirname(path))
        code = variant_code(qualifier)
        if code == SOURCE_LOCALE:
            continue
        done = translated.setdefault(code, set())
        for name, text in read_strings(path).items():
            if name in source and source[name] != text:
                done.add(name)

    result: dict[str, tuple[int, int]] = {
        SOURCE_LOCALE: (total, total),
    }
    for code, done in translated.items():
        result[code] = (len(done), total)
    return dict(sorted(result.items()))


def render(entries: dict[str, tuple[int, int]]) -> str:
    width = max(len(code) for code in entries)
    lines = ["    private val coverage = mapOf("]
    lines.append(f"        {SOURCE_LOCALE!r}".replace("'", '"')
                 + f' to LocaleCoverage("{SOURCE_LOCALE}", '
                 + f"{entries[SOURCE_LOCALE][0]}, {entries[SOURCE_LOCALE][1]}),")
    for code, (done, total) in entries.items():
        if code == SOURCE_LOCALE:
            continue
        key = f'"{code}"'.ljust(width + 2)
        lines.append(f"        {key} to LocaleCoverage(\"{code}\", {done}, {total}),")
    lines.append("    )")
    return "\n".join(lines)


BLOCK = re.compile(
    r"    private val coverage = mapOf\(.*?\n    \)",
    re.DOTALL,
)


def shadowed_locales() -> list[tuple[str, str]]:
    """Findet Sprachen mit zusätzlicher Regions-Variante.

    Android gewinnt bei `values-de-rDE` gegen `values-de`, weil der
    Sprachcode spezifischer ist. Die handgepflegte `values-de` (du-Form,
    kurze Buttons) würde dadurch von der maschinellen `values-de-rDE`
    überschrieben — sichtbar als „Zuhause" statt „Home" oder „DEUT"
    statt „DEMO". Deshalb darf es pro Sprache nur einen Katalog geben.
    """
    bare: set[str] = set()
    variants: dict[str, str] = {}
    for path in sorted(glob.glob(os.path.join(RES, "values-*", "strings.xml"))):
        qualifier = os.path.basename(os.path.dirname(path))
        code = qualifier.removeprefix("values-")
        base = variant_code(qualifier)
        if code == base:
            bare.add(base)
        else:
            variants.setdefault(base, qualifier)
    return [(q, c) for c, q in sorted(variants.items()) if c in bare]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true",
                        help="nur prüfen, nicht schreiben")
    args = parser.parse_args()

    shadows = shadowed_locales()
    if shadows:
        names = ", ".join(f"{variant} verdeckt {code}" for variant, code in shadows)
        print(f"FEHLER: {names} — die handgepflegte Variante würde gewinnen.\n"
              f"  Nur einen Katalog je Sprache pflegen.", file=sys.stderr)
        return 1

    entries = collect()
    block = render(entries)
    source = open(TARGET, encoding="utf-8").read()
    match = BLOCK.search(source)
    if not match:
        print(f"FEHLER: Coverage-Tabelle in {TARGET} nicht gefunden", file=sys.stderr)
        return 1

    if args.check:
        if match.group(0) != block:
            print("FEHLER: Coverage-Tabelle ist veraltet — bitte ausführen:\n"
                  "  python3 tools/update_locale_coverage.py", file=sys.stderr)
            return 1
        print(f"Coverage-Tabelle aktuell ({len(entries)} Sprachen)")
        return 0

    open(TARGET, "w", encoding="utf-8").write(
        source[:match.start()] + block + source[match.end():])
    print(f"Coverage-Tabelle aktualisiert ({len(entries)} Sprachen):")
    for code, (done, total) in entries.items():
        print(f"  {code:5} {done:>4}/{total}  {done * 100 // total:>3}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
