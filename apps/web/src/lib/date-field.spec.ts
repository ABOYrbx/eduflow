import {
  firstWeekday,
  formatIsoDate,
  monthGrid,
  parseIsoDate,
  shiftMonth,
  stepIsoDate,
  toIsoDate,
  weekStartIso,
  weekdayNames,
} from "./date-field";

describe("parseIsoDate", () => {
  it("liest gültige Werte", () => {
    const date = parseIsoDate("2026-09-29");
    expect(date?.getFullYear()).toBe(2026);
    expect(date?.getMonth()).toBe(8);
    expect(date?.getDate()).toBe(29);
  });

  it("lehnt Unsinn ab", () => {
    expect(parseIsoDate("2026-13-01")).toBeNull();
    expect(parseIsoDate("2026-02-31")).toBeNull();
    expect(parseIsoDate("29.09.2026")).toBeNull();
    expect(parseIsoDate("")).toBeNull();
    expect(parseIsoDate(null)).toBeNull();
  });

  it("verliert keinen Tag durch Zeitzonen", () => {
    expect(toIsoDate(new Date(2026, 0, 1))).toBe("2026-01-01");
  });
});

describe("stepIsoDate", () => {
  it("geht tage- und wochenweise", () => {
    expect(stepIsoDate("2026-09-29", 1)).toBe("2026-09-30");
    expect(stepIsoDate("2026-09-29", 7)).toBe("2026-10-06");
    expect(stepIsoDate("2026-09-01", -1)).toBe("2026-08-31");
  });

  it("wechselt monatsweise über das Jahr", () => {
    expect(stepIsoDate("2026-01-15", 0, 1)).toBe("2026-02-15");
    expect(stepIsoDate("2026-12-15", 0, 1)).toBe("2027-01-15");
    expect(stepIsoDate("2026-01-15", 0, -1)).toBe("2025-12-15");
  });

  it("schneidet auf den letzten Tag des Monats", () => {
    expect(stepIsoDate("2026-01-31", 0, 1)).toBe("2026-02-28");
  });

  it("lässt ungültige Werte unverändert", () => {
    expect(stepIsoDate("kein-datum", 3)).toBe("kein-datum");
  });
});

describe("monthGrid", () => {
  it("liefert immer 42 Tage", () => {
    expect(monthGrid(2026, 8, 0)).toHaveLength(42);
    expect(monthGrid(2026, 1, 6)).toHaveLength(42);
  });

  it("beginnt am gewählten Wochenanfang", () => {
    // September 2026 beginnt am Dienstag → bei Montagswoche zwei Tage davor.
    expect(monthGrid(2026, 8, 0)[0]).toBe("2026-08-31");
    expect(monthGrid(2026, 8, 6)[0]).toBe("2026-08-30");
  });

  it("enthält den ersten des Monats", () => {
    expect(monthGrid(2026, 8, 0)).toContain("2026-09-01");
  });
});

describe("shiftMonth", () => {
  it("rechnet über den Jahreswechsel", () => {
    expect(shiftMonth(2026, 11, 1)).toEqual({ year: 2027, month: 0 });
    expect(shiftMonth(2026, 0, -1)).toEqual({ year: 2025, month: 11 });
  });
});

describe("weekStartIso", () => {
  it("findet den Wochenanfang", () => {
    // 29.09.2026 ist ein Dienstag.
    expect(weekStartIso("2026-09-29", 0)).toBe("2026-09-28");
    expect(weekStartIso("2026-09-29", 6)).toBe("2026-09-27");
  });
});

describe("Formatierung", () => {
  it("zeigt das Datum in der Zielsprache", () => {
    expect(formatIsoDate("2026-09-29", "de-DE")).toBe("29.09.2026");
    expect(formatIsoDate("2026-09-29", "en-US")).toBe("09/29/2026");
  });

  it("gibt ungültige Werte unverändert zurück", () => {
    expect(formatIsoDate("nope", "de-DE")).toBe("nope");
  });

  it("liefert sieben Wochentagsnamen in der Reihenfolge des Wochenanfangs", () => {
    expect(weekdayNames("de-DE", 0)[0]).toMatch(/^Mo/);
    expect(weekdayNames("de-DE", 0)[6]).toMatch(/^So/);
    // Sonntag als Wochenanfang verschiebt die Liste.
    expect(weekdayNames("de-DE", 6)[0]).toMatch(/^So/);
    expect(weekdayNames("en-US", 0)[0]).toMatch(/^Mo/);
  });
});

describe("firstWeekday", () => {
  it("bildet Intl 1..7 (Mo..So) auf 0..6 ab", () => {
    expect(firstWeekday("de-DE")).toBe(0); // Montag
    expect(firstWeekday("en-US")).toBe(6); // Sonntag
  });

  it("fällt bei unbekannter Sprache auf Montag zurück", () => {
    expect(firstWeekday("")).toBe(0);
  });
});
