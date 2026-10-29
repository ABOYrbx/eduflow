import { LOCALE_COVERAGE } from "./locale-coverage.generated";

describe("locale-coverage (generiert)", () => {
  it("enthält alle Katalog-Sprachen genau einmal", () => {
    const codes = LOCALE_COVERAGE.map((row) => row.code);
    expect(codes.length).toBeGreaterThan(0);
    expect(new Set(codes).size).toBe(codes.length);
    expect(codes).toContain("en");
    expect(codes).toContain("de");
  });

  it("Prozente liegen zwischen 0 und 100, Englisch bei 100", () => {
    for (const row of LOCALE_COVERAGE) {
      expect(row.percent).toBeGreaterThanOrEqual(0);
      expect(row.percent).toBeLessThanOrEqual(100);
      expect(row.translated).toBeLessThanOrEqual(row.total);
      expect(row.total).toBeGreaterThan(0);
    }
    expect(LOCALE_COVERAGE.find((row) => row.code === "en")?.percent).toBe(100);
  });
});
