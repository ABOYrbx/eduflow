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
/** Platzhalter wie {count} sind Namen aus dem englischen Quelltext, keine
 *  Wörter. Mitgezählt machen sie jeden Wert zum Treffer. */
const PLATZHALTER = /\{[^{}]*\}/g;
const KOGNITE = new Set([
  "token", "kalender", "titel", "datum", "profil", "alle", "morgen",
  "lektion", "note", "liste", "faktor", "ller", "modus", "lokale",
  "konto", "licht", "typ", "typen", "termin", "test", "cache", "kopier",
  "geload", "violet", "speicher", "standort", "chat", "nachricht",
  "laden", "kopiert", "desc", "standardfilter",
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
  deutschWoerter: Set<string>,
): string[] {
  const treffer: string[] = [];
  for (const [key, wert] of Object.entries(catalog)) {
    if (!(key in en) || wert === en[key]) continue;
    if (key in de && normalisiert(de[key]) !== normalisiert(en[key]) && normalisiert(wert) === normalisiert(de[key]) && !KEEP_WERTE[sprache]?.has(wert)) {
      treffer.push(`${key} = ${wert}`);
      continue;
    }
    // Nur Wörter, die nicht auch im englischen Quelltext stehen: 'EduFlow'
    // oder 'Cache' sind in jeder Sprache gleich und kein deutsches Indiz.
    const gemeinsam = new Set(words((en[key] ?? "").replace(PLATZHALTER, " ")));
    const woerter = words(wert.replace(PLATZHALTER, " ")).filter((wort) => !gemeinsam.has(wort));
    if (woerter.length === 0) continue;
    const trefferWoerter = woerter.filter((wort) => deutschWoerter.has(wort) && !KOGNITE.has(wort));
    const istDeutsch = woerter.length === 1
      ? trefferWoerter.length === 1
      : trefferWoerter.length / woerter.length >= 0.5;
    if (istDeutsch) treffer.push(`${key} = ${wert}`);
  }
  return treffer;
}

describe("Web-Kataloge", () => {
  const catalogs = lade("messages");
  const en = catalogs.get("en") as Record<string, string>;
  const de = catalogs.get("de") as Record<string, string>;
  const deutschWoerter = new Set<string>(
    JSON.parse(readFileSync(join(__dirname, "..", "..", "..", "..", "migration", "de-vokabular.json"), "utf8")) as string[],
  );

  it("unterscheiden sich auf Deutsch wirklich von der Quelle", () => {
    // Ohne diesen Test wäre die Prüfung unten bedeutungslos.
    expect(Object.keys(en).filter((key) => de[key] !== en[key]).length).toBeGreaterThan(100);
  });

  it("kennt auch deutsche Wörter, die nicht mehr in de.json stehen", () => {
    // Genau hier ist die Prüfung im September 2026 gescheitert: die Reste
    // stammen aus einer älteren deutschen Fassung ('Vertretungsplan',
    // waehrend de.json heute 'Ersetzungsplan' sagt). Ein Wortschatz aus
    // de.json allein sieht davon nichts.
    for (const wort of ["vertretungsplan", "aufgaben", "darstellung", "pfeilen"]) {
      expect(deutschWoerter.has(wort)).toBe(true);
    }
  });

  for (const [sprache, catalog] of catalogs) {
    if (sprache === "en" || sprache === "de") continue;

    it(`${sprache} zeigt keine deutschen Texte`, () => {
      expect(meldeDeutscheReste(en, de, catalog, sprache, deutschWoerter)).toEqual([]);
    });

    it(`${sprache} kennt jeden Quell-Key`, () => {
      expect(Object.keys(en).filter((key) => catalog[key] === undefined)).toEqual([]);
    });
  }
});
