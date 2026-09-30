import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
/** Unicode-Normalisierung, damit zerlegte und zusammengesetzte Umlaute
 *  (A + U+0308 gegen A-diaeresis) als dasselbe gelten. */
function nfc(text: string | undefined): string {
  return (text ?? "").normalize("NFC");
}

/**
 * Wächter über die Kataloge: eine Sprache, die noch nicht übersetzt ist,
 * darf **keinen deutschen Text** anzeigen, sondern den englischen
 * Originaltext. Sonst sieht „Polski" nach einem halb übersetzten deutschen
 * Interface aus, sobald Crowdin wieder deutsche Werte in leere Schlüssel
 * schreibt.
 *
 * Dieselben beiden Regeln wie `migration/check-catalogs.py`, bewusst
 * konservativ, damit echte Kognite nicht mitgerissen werden ('Datum:' ist im
 * Niederländischen richtig). Was sie nicht fassen, meldet das Skript.
 */

const WORT = /[A-Za-zÄÖÜäöüß]{4,}/g;
const NORMAL = /[^a-zäöüß]/g;
const KOGNITE = new Set([
  "token", "kalender", "titel", "datum", "profil", "alle", "morgen",
  "lektion", "note", "liste", "faktor", "ller", "modus", "lokale",
  "konto", "licht",
]);
const ABDECKUNG_GUT = 200;
// Ganze Werte, die in der jeweiligen Sprache richtig sind und dem Deutschen
// nur gleichen: 'Datum:' ist im Tschechischen und Niederlaendischen richtig,
// 'Alle typen' im Niederlaendischen, '{lesson}. lektion' in Daenisch und
// Schwedisch.
const KEEP_WERTE: Record<string, Set<string>> = {
  cs: new Set(["Datum:"]),
  da: new Set(["{lesson}. lektion"]),
  nl: new Set(["Datum:", "Alle typen"]),
  sv: new Set(["{lesson}. lektion"]),
};

function flat(node: unknown, prefix = "", out: Record<string, string> = {}): Record<string, string> {
  if (typeof node === "object" && node !== null) {
    for (const [key, value] of Object.entries(node)) flat(value, `${prefix}${key}.`, out);
  } else if (typeof node === "string") {
    out[prefix.slice(0, -1)] = node;
  }
  return out;
}

function words(value: string): string[] {
  return (value.toLowerCase().match(WORT) ?? []);
}

function normalisiert(value: string | undefined): string {
  return nfc(value).toLowerCase().replace(NORMAL, "");
}

function lade(verzeichnis: string): Map<string, Record<string, string>> {
  const ordner = join(__dirname, "..", "..", verzeichnis);
  return new Map(readdirSync(ordner)
    .filter((name) => name.endsWith(".json"))
    .map((name) => [name.replace(/\.json$/, ""), flat(JSON.parse(readFileSync(join(ordner, name), "utf8")))]));
}

/** Regeln als reine Funktion, damit beide Katalogsätze sie teilen. */
export function meldeDeutscheReste(
  en: Record<string, string>,
  de: Record<string, string>,
  catalog: Record<string, string>,
  sprache: string,
): string[] {
  const deutschWoerter = new Set<string>();
  for (const [key, wert] of Object.entries(de)) {
    const quelle = en[key] ?? "";
    for (const wort of words(wert)) if (!words(quelle).includes(wort)) deutschWoerter.add(wort);
  }
  const echt = Object.keys(catalog).filter((key) => key in en && catalog[key] !== en[key] && catalog[key] !== de[key]).length;
  const gering = echt < ABDECKUNG_GUT;

  const treffer: string[] = [];
  for (const [key, wert] of Object.entries(catalog)) {
    if (!(key in en) || wert === en[key]) continue;
    if (key in de && normalisiert(de[key]) !== normalisiert(en[key]) && normalisiert(wert) === normalisiert(de[key]) && !KEEP_WERTE[sprache]?.has(wert)) {
      treffer.push(`${key} = ${wert}`);
      continue;
    }
    const woerter = words(wert);
    if (woerter.length === 0) continue;
    const trefferWoerter = woerter.filter((wort) => deutschWoerter.has(wort) && !KOGNITE.has(wort));
    const istDeutsch = woerter.length === 1
      ? trefferWoerter.length === 1
      : trefferWoerter.length / woerter.length >= 0.6;
    if (istDeutsch) treffer.push(`${key} = ${wert}`);
  }
  return treffer;
}

describe("Web-Kataloge", () => {
  const catalogs = lade("messages");
  const en = catalogs.get("en") as Record<string, string>;
  const de = catalogs.get("de") as Record<string, string>;

  it("unterscheiden sich auf Deutsch wirklich von der Quelle", () => {
    // Ohne diesen Test wäre die Prüfung unten bedeutungslos.
    expect(Object.keys(en).filter((key) => de[key] !== en[key]).length).toBeGreaterThan(100);
  });

  for (const [sprache, catalog] of catalogs) {
    if (sprache === "en" || sprache === "de") continue;

    it(`${sprache} zeigt keine deutschen Texte`, () => {
      expect(meldeDeutscheReste(en, de, catalog, sprache)).toEqual([]);
    });

    it(`${sprache} kennt jeden Quell-Key`, () => {
      expect(Object.keys(en).filter((key) => catalog[key] === undefined)).toEqual([]);
    });
  }
});
