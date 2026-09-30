import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
/** Unicode-Normalisierung, damit zerlegte und zusammengesetzte Umlaute
 *  (A + U+0308 gegen A-diaeresis) als dasselbe gelten. */
function nfc(text: string | undefined): string {
  return (text ?? "").normalize("NFC");
}

/**
 * Wächter über die Backend-Kataloge: nicht übersetzte Sprachen dürfen keinen
 * deutschen Text liefern, sondern den englischen Quelltext. Fehlertexte und
 * Beschriftungen des Settings-Schemas kommen hierher und stehen sonst deutsch
 * in einer englischen Oberfläche.
 *
 * Dieselben beiden Regeln wie `migration/check-catalogs.py`.
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

const words = (value: string): string[] => value.toLowerCase().match(WORT) ?? [];
const normalisiert = (value: string | undefined): string => nfc(value).toLowerCase().replace(NORMAL, "");

// Die Spec liegt in src/messages, die Kataloge also direkt daneben.
const catalogs = new Map(readdirSync(__dirname)
  .filter((name) => name.endsWith(".json"))
  .map((name) => [name.replace(/\.json$/, ""), flat(JSON.parse(readFileSync(join(__dirname, name), "utf8")))] as const));

const en = catalogs.get("en") as Record<string, string>;
const de = catalogs.get("de") as Record<string, string>;

// Wortschatz aus migration/de-vokabular.json, nicht aus de.json: die
// deutschen Reste stammen aus einer aelteren Fassung und stehen in keiner
// aktuellen Datei mehr. Siehe build-de-vocab.py.
const deutschWoerter = new Set<string>(
  JSON.parse(readFileSync(join(__dirname, "..", "..", "..", "..", "migration", "de-vokabular.json"), "utf8")) as string[],
);

function melde(catalog: Record<string, string>, sprache: string): string[] {
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

describe("Backend-Kataloge", () => {
  it("unterscheiden sich auf Deutsch wirklich von der Quelle", () => {
    expect(Object.keys(en).filter((key) => de[key] !== en[key]).length).toBeGreaterThan(50);
  });

  it("kennt auch deutsche Wörter, die nicht mehr in de.json stehen", () => {
    // Genau hier ist die Prüfung im September 2026 gescheitert.
    expect(deutschWoerter.has("vertretungsplan")).toBe(true);
    expect(deutschWoerter.has("anwesenheitsmeldungen")).toBe(true);
  });

  for (const [sprache, catalog] of catalogs) {
    if (sprache === "en" || sprache === "de") continue;
    it(`${sprache} zeigt keine deutschen Texte`, () => {
      expect(melde(catalog, sprache)).toEqual([]);
    });
  }
});
