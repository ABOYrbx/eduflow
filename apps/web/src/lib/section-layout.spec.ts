import {
  hitIndexByMidline,
  moveItem,
  normalizeHidden,
  normalizeOrder,
  normalizeSpans,
  SECTION_KEYS,
  SPAN_FULL,
  SPAN_HALF,
  spanOf,
  serializeSpans,
  toggleSpan,
} from "./section-layout";

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

describe("hitIndexByMidline", () => {
  const rects = [
    { top: 0, bottom: 100 },
    { top: 100, bottom: 200 },
    { top: 200, bottom: 300 },
  ];

  it("nimmt die Zeile, in der der Zeiger steht", () => {
    expect(hitIndexByMidline(rects, 10, 0)).toBe(0);
    expect(hitIndexByMidline(rects, 190, 0)).toBe(1);
  });

  it("bleibt vor der ersten Karte beim Fallback", () => {
    expect(hitIndexByMidline(rects, -50, 1)).toBe(1);
  });

  it("behaelt ausserhalb der Karten den letzten bekannten Index", () => {
    // Beim Ziehen ueber oder unter das Raster soll die Karte nicht springen.
    expect(hitIndexByMidline(rects, 500, 2)).toBe(2);
    expect(hitIndexByMidline(rects, -50, 0)).toBe(0);
  });
});

describe("Spaltenbreiten", () => {
  it("liest nur gueltige Paare", () => {
    expect(normalizeSpans("weather:6,homework:12")).toEqual({ weather: 6, homework: 12 });
    expect(normalizeSpans("messages:9,lunch:6")).toEqual({});
    expect(normalizeSpans("")).toEqual({});
  });

  it("faellt auf volle Breite zurueck", () => {
    expect(spanOf({}, "messages")).toBe(SPAN_FULL);
    expect(spanOf({ messages: 6 }, "messages")).toBe(SPAN_HALF);
    expect(spanOf({ messages: 9 }, "messages")).toBe(SPAN_FULL);
  });

  it("wechselt zwischen halb und voll", () => {
    expect(toggleSpan({}, "messages")).toEqual({ messages: 6 });
    expect(toggleSpan({ messages: 6 }, "messages")).toEqual({ messages: SPAN_FULL });
  });

  it("schreibt nur halbe Breiten, in fester Reihenfolge", () => {
    expect(serializeSpans({ weather: 6, messages: 6 }, ["messages", "homework", "weather"]))
      .toBe("messages:6,weather:6");
    expect(serializeSpans({}, ["messages"])).toBe("");
  });
});
