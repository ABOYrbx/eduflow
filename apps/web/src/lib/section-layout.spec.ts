import { hitIndex, moveItem, normalizeHidden, normalizeOrder, SECTION_KEYS } from "./section-layout";

describe("normalizeOrder", () => {
  it("ergänzt fehlende Abschnitte am Ende", () => {
    expect(normalizeOrder("homework")).toEqual(["homework", "messages", "weather"]);
  });

  it("wirft unbekannte Werte raus und entdoppelt", () => {
    expect(normalizeOrder("homework,homework,lunch,messages")).toEqual(["homework", "messages", "weather"]);
  });

  it("fällt ohne Wert auf die Standardreihenfolge zurück", () => {
    expect(normalizeOrder(undefined)).toEqual(SECTION_KEYS);
  });
});

describe("normalizeHidden", () => {
  it("behält nur bekannte Schlüssel", () => {
    expect(normalizeHidden("weather,lunch")).toEqual(["weather"]);
  });

  it("leerer Wert bedeutet nichts ausgeblendet", () => {
    expect(normalizeHidden("")).toEqual([]);
    expect(normalizeHidden(undefined)).toEqual([]);
  });
});

describe("moveItem", () => {
  const list = ["a", "b", "c"];

  it("verschiebt nach unten", () => {
    expect(moveItem(list, 0, 1)).toEqual(["b", "a", "c"]);
  });

  it("verschiebt nach oben", () => {
    expect(moveItem(list, 2, 0)).toEqual(["c", "a", "b"]);
  });

  it("schneidet Ziele ausserhalb der Liste ab", () => {
    expect(moveItem(list, 0, 99)).toEqual(["b", "c", "a"]);
    expect(moveItem(list, 0, -5)).toEqual(["a", "b", "c"]);
  });

  it("verändert die Eingabe nicht", () => {
    moveItem(list, 0, 2);
    expect(list).toEqual(["a", "b", "c"]);
  });

  it("ungültige Quellposition ändert nichts", () => {
    expect(moveItem(list, 7, 0)).toEqual(["a", "b", "c"]);
  });
});

describe("hitIndex", () => {
  const rects = [
    { top: 0, bottom: 50 },
    { top: 50, bottom: 100 },
    { top: 100, bottom: 150 },
  ];

  it("findet die Zeile am Zeiger", () => {
    expect(hitIndex(rects, 10, 0)).toBe(0);
    expect(hitIndex(rects, 75, 0)).toBe(1);
    expect(hitIndex(rects, 149, 0)).toBe(2);
  });

  it("nutzt den letzten bekannten Index ausserhalb aller Zeilen", () => {
    expect(hitIndex(rects, -20, 1)).toBe(1);
    expect(hitIndex(rects, 400, 2)).toBe(2);
  });
});
