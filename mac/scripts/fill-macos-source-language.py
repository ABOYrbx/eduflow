#!/usr/bin/env python3
"""macOS-String-Katalog: fehlende englische Quelltexte ergänzen.

`sourceLanguage` ist bereits "en", aber 87 aktive Keys haben einen leeren
`localizations`-Block – meist englische Literale wie "All homework", die als
Key direkt im Swift-Code stehen. Ohne `en`-Eintrag hat der Katalog keinen
übersetzbaren Quelltext: Crowdin sieht eine leere Zeichenkette.

Der Schlüssel IST hier bereits der englische Text, deshalb wird er als
Quelltext übernommen. Bestehende Übersetzungen bleiben unangetastet; nur
fehlende `en`-Blöcke werden ergänzt. Keys mit `extractionState: stale`
kommen nicht vor (sie stehen nicht mehr im Code).

Die Datei wird im Xcode-Stil geschrieben (Einrückung 2, Leerzeichen vor dem
Doppelpunkt, leere Objekte als `{\n\n  }`), damit der Diff nur die ergänzten
Quelltexte zeigt und Crowdin-Syncs nicht anschlägt.
"""
import json
import re
from pathlib import Path

path = Path(__file__).resolve().parent.parent / "EduFlow" / "Resources" / "Localizable.xcstrings"
data = json.loads(path.read_text(encoding="utf-8"))

assert data.get("sourceLanguage") == "en", "sourceLanguage muss en sein"

added, skipped_stale = [], []
for key, entry in data["strings"].items():
    if entry.get("extractionState") == "stale":
        if "en" not in entry.get("localizations", {}):
            skipped_stale.append(key)
        continue
    localizations = entry.setdefault("localizations", {})
    if "en" in localizations:
        continue
    localizations["en"] = {"stringUnit": {"state": "translated", "value": key}}
    added.append(key)

# Schlüsselreihenfolge bleibt, wie Xcode sie geschrieben hat.
text = json.dumps(data, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n"
# Python schreibt leere Objekte als `{}`, Xcode als_block_ mit Leerzeile.
def leeres_objekt(treffer: "re.Match[str]") -> str:
    einrueckung = treffer.group(1)
    return einrueckung + "{\n\n" + einrueckung + "}"


text = re.sub(r"(?m)^(\s*)\{\}$", leeres_objekt, text)
path.write_text(text, encoding="utf-8")

print(f"englische Quelltexte ergänzt: {len(added)}")
print(f"stale Keys ohne en (unberührt): {len(skipped_stale)}")