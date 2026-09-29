import en from "../../messages/en.json";

type Vars = Record<string, string | number>;

/** Englisch ist Quellsprache und Fallback (Crowdin liefert weitere Kataloge). */
export const FALLBACK_LOCALE = "en";
export const LOCALE_COOKIE = "eduflow_locale";

/** Cookie-String für die Sprachwahl (1 Jahr, eigener Pfad, Lax). */
export function localeCookie(code: string): string {
  return `${LOCALE_COOKIE}=${code}; path=/; max-age=31536000; SameSite=Lax`;
}

/** Zusätzliche Kataloge (der Server registriert alle via lib/locales). */
const extraCatalogs: Record<string, unknown> = {};
export function registerCatalogs(catalogs: Record<string, unknown>): void {
  for (const [locale, catalog] of Object.entries(catalogs)) extraCatalogs[locale] = catalog;
}
export function supportedLocales(): string[] {
  return [FALLBACK_LOCALE, ...Object.keys(extraCatalogs)];
}
export function getCatalog(locale: string): unknown {
  return locale !== FALLBACK_LOCALE && extraCatalogs[locale] ? extraCatalogs[locale] : en;
}

/** Eigennamen der Sprachen (Crowdin-Neuzugänge fallen auf den Code zurück). */
export const NATIVE_NAMES: Record<string, string> = {
  af: "Afrikaans", ar: "العربية", ca: "Català", cs: "Čeština", da: "Dansk",
  de: "Deutsch", el: "Ελληνικά", en: "English", es: "Español", fi: "Suomi",
  fr: "Français", he: "עברית", hu: "Magyar", it: "Italiano", ja: "日本語",
  ko: "한국어", nl: "Nederlands", no: "Norsk", pl: "Polski", pt: "Português",
  ro: "Română", ru: "Русский", sr: "Српски", sv: "Svenska", tr: "Türkçe",
  uk: "Українська", vi: "Tiếng Việt", zh: "中文",
};

/** Eingespritzter Katalog (das Layout bettet ihn pro Request ein). */
declare global {
  interface Window {
    __EDUFLOW_MESSAGES__?: { locale: string; catalog: unknown; supported: string[] };
  }
}
function injected(): { locale: string; catalog: unknown } | null {
  if (typeof window === "undefined") return null;
  const payload = window.__EDUFLOW_MESSAGES__;
  if (!payload || typeof payload.locale !== "string" || typeof payload.catalog !== "object" || payload.catalog === null) return null;
  return { locale: payload.locale, catalog: payload.catalog };
}

/**
 * Aktive Sprache im Browser (setzt der LocaleProvider nach der Hydration,
 * damit der erste Client-Render mit dem Server-HTML auf Englisch übereinstimmt).
 */
let activeLocale: string | null = null;
export function setActiveLocale(locale: string | null): void {
  activeLocale = locale;
}

/**
 * BCP47-Tag für toLocale*-Aufrufe: aktive Sprache, sonst Englisch.
 * Auf dem Server und beim ersten Client-Render (Hydration) ist das Englisch,
 * damit der Client das Server-HTML übernimmt; der LocaleProvider aktiviert
 * danach die injizierte Sprache und rendert neu.
 */
export function localeTag(): string {
  return activeLocale ?? FALLBACK_LOCALE;
}

/** "en-US" → "en"; alles andere (leer, zu lang, keine Buchstaben) → null. */
export function normalizeLocaleTag(tag: unknown): string | null {
  if (typeof tag !== "string") return null;
  const primary = tag.toLowerCase().split("-")[0]?.split("_")[0]?.trim() ?? "";
  return /^[a-z]{2}$/.test(primary) ? primary : null;
}

/** "fr-FR,fr;q=0.9" → ["fr", "fr"]. */
export function parseAcceptLanguage(header: string | null | undefined): string[] {
  if (!header) return [];
  const out: string[] = [];
  for (const part of header.split(",")) {
    const tag = normalizeLocaleTag(part.split(";")[0]?.trim() ?? "");
    if (tag) out.push(tag);
  }
  return out;
}

/** Erste unterstützte Sprache aus den Kandidaten, sonst Englisch. */
export function resolveLocale(candidates: Array<string | null | undefined>, supported: string[] = supportedLocales()): string {
  for (const candidate of candidates) {
    const tag = normalizeLocaleTag(candidate);
    if (tag && supported.includes(tag)) return tag;
  }
  return FALLBACK_LOCALE;
}

function lookup(catalog: unknown, key: string): string | undefined {
  let node: unknown = catalog;
  for (const part of key.split(".")) {
    if (typeof node !== "object" || node === null) return undefined;
    node = (node as Record<string, unknown>)[part];
  }
  return typeof node === "string" ? node : undefined;
}

export function t(key: string, vars?: Vars, locale?: string): string {
  const injection = injected();
  let catalog: unknown = en;
  if (locale && locale !== FALLBACK_LOCALE && extraCatalogs[locale]) {
    catalog = extraCatalogs[locale];
  } else if (!locale && activeLocale && injection && injection.locale === activeLocale) {
    catalog = injection.catalog;
  }
  const out = lookup(catalog, key) ?? lookup(en, key) ?? key;
  if (!vars) return out;
  let text = out;
  for (const [name, value] of Object.entries(vars)) text = text.split(`{${name}}`).join(String(value));
  return text;
}
