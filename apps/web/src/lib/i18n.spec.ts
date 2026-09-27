import {
  getCatalog,
  normalizeLocaleTag,
  parseAcceptLanguage,
  registerCatalogs,
  resolveLocale,
  setActiveLocale,
  supportedLocales,
  t,
} from "./i18n";

registerCatalogs({
  fr: { nav: { overview: "Aperçu" }, onlyFr: "Seulement FR" },
  en: { nav: { overview: "Overview" } },
});

describe("t", () => {
  afterEach(() => {
    setActiveLocale(null);
    delete (globalThis as { window?: unknown }).window;
  });

  it("liefert Deutsch als Standard", () => {
    expect(t("nav.overview")).toBe("Übersicht");
  });

  it("ersetzt Variablen", () => {
    expect(t("overview.newMessages", { count: 3 })).toBe("3 neu");
  });

  it("gibt unbekannte Keys unverändert zurück", () => {
    expect(t("does.not.exist")).toBe("does.not.exist");
  });

  it("nutzt die gewünschte Sprache", () => {
    expect(t("nav.overview", undefined, "fr")).toBe("Aperçu");
  });

  it("fällt für fehlende Keys auf Deutsch zurück", () => {
    expect(t("nav.messages", undefined, "fr")).toBe("Nachrichten");
  });

  it("fällt für unbekannte Sprachen auf Deutsch zurück", () => {
    expect(t("nav.overview", undefined, "xx")).toBe("Übersicht");
  });

  it("nutzt den eingespritzten Katalog erst nach Aktivierung", () => {
    (globalThis as { window?: unknown }).window = {
      __EDUFLOW_MESSAGES__: { locale: "fr", catalog: { nav: { overview: "Aperçu" } }, supported: ["de", "fr"] },
    };
    expect(t("nav.overview")).toBe("Übersicht");
    setActiveLocale("fr");
    expect(t("nav.overview")).toBe("Aperçu");
  });
});

describe("getCatalog/supportedLocales", () => {
  it("liefert registrierte Kataloge und Deutsch als Fallback", () => {
    expect(getCatalog("fr")).toEqual({ nav: { overview: "Aperçu" }, onlyFr: "Seulement FR" });
    expect(getCatalog("xx")).toEqual(getCatalog("de"));
  });

  it("listet Deutsch zuerst", () => {
    const locales = supportedLocales();
    expect(locales[0]).toBe("de");
    expect(locales).toContain("fr");
  });
});

describe("normalizeLocaleTag", () => {
  it("kürzt Region und normalisiert", () => {
    expect(normalizeLocaleTag("fr-FR")).toBe("fr");
    expect(normalizeLocaleTag("EN_us")).toBe("en");
    expect(normalizeLocaleTag("de")).toBe("de");
  });

  it("lehnt Ungültiges ab", () => {
    expect(normalizeLocaleTag("")).toBeNull();
    expect(normalizeLocaleTag("e")).toBeNull();
    expect(normalizeLocaleTag("eng")).toBeNull();
    expect(normalizeLocaleTag("de!")).toBeNull();
    expect(normalizeLocaleTag(null)).toBeNull();
    expect(normalizeLocaleTag(42)).toBeNull();
  });
});

describe("parseAcceptLanguage", () => {
  it("ordnet nach Auftreten und ignoriert q-Werte", () => {
    expect(parseAcceptLanguage("fr-FR,fr;q=0.9,en;q=0.8")).toEqual(["fr", "fr", "en"]);
  });

  it("leere Header geben leere Liste", () => {
    expect(parseAcceptLanguage(null)).toEqual([]);
    expect(parseAcceptLanguage("")).toEqual([]);
  });
});

describe("resolveLocale", () => {
  const supported = ["de", "en", "fr"];

  it("nimmt den ersten unterstützten Kandidaten (Cookie zuerst)", () => {
    expect(resolveLocale(["fr", "en"], supported)).toBe("fr");
    expect(resolveLocale([null, "en"], supported)).toBe("en");
  });

  it("überspringt Nicht-Unterstütztes und fällt auf Deutsch zurück", () => {
    expect(resolveLocale(["xx", "fr"], supported)).toBe("fr");
    expect(resolveLocale(["xx", null], supported)).toBe("de");
    expect(resolveLocale([], supported)).toBe("de");
  });
});
