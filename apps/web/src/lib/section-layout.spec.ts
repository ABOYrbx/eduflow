import {
  hitIndexByMidline,
  moveItem,
  moveSection,
  moveSectionTo,
  sectionFlags,
  toggleHidden,
  toggleSectionWidth,
  type SectionState,
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

  // ---------------------------------------- Übergänge des Layouts
  //
  // `SectionBar` und `SectionEditor` bieten dieselben drei Elemente und
  // benutzen diese Funktionen beide — sonst rechnete jede Stelle ihre
  // Callbacks selbst.

  const base = (): SectionState => ({
    order: ["messages", "homework", "weather"],
    hidden: [],
    spans: {},
  });

  describe("Layout-Übergänge", () => {
    it("verschiebt einen Abschnitt um eine Position", () => {
      expect(moveSection(base(), 0, 1).order).toEqual(["homework", "messages", "weather"]);
      expect(moveSection(base(), 2, -1).order).toEqual(["messages", "weather", "homework"]);
    });

    it("schneidet am Anfang und am Ende ab", () => {
      expect(moveSection(base(), 0, -1).order).toEqual(base().order);
      expect(moveSection(base(), 2, 1).order).toEqual(base().order);
    });

    it("verändert beim Verschieben nichts ausser der Reihenfolge", () => {
      const next = moveSection(base(), 0, 1);
      expect(next.hidden).toEqual([]);
      expect(next.spans).toEqual({});
    });

    it("zieht einen Abschnitt auf eine Zielposition", () => {
      expect(moveSectionTo(base(), 0, 2).order).toEqual(["homework", "weather", "messages"]);
      // Grenzen werden abgeschnitten wie beim Verschieben.
      expect(moveSectionTo(base(), 1, 9).order).toEqual(["messages", "weather", "homework"]);
    });

    it("blendet aus und wieder ein", () => {
      const hidden = toggleHidden(base(), "weather");
      expect(hidden.hidden).toEqual(["weather"]);
      expect(toggleHidden(hidden, "weather").hidden).toEqual([]);
    });

    it("behaelt beim Ein- und Ausblenden die uebrigen Abschnitte", () => {
      const state: SectionState = { ...base(), hidden: ["weather"] };
      expect(toggleHidden(state, "messages").hidden).toEqual(["weather", "messages"]);
    });

    it("wechselt die Breite eines Abschnitts", () => {
      expect(toggleSectionWidth(base(), "messages").spans).toEqual({ messages: SPAN_HALF });
      const half = toggleSectionWidth(base(), "messages");
      expect(toggleSectionWidth(half, "messages").spans).toEqual({ messages: SPAN_FULL });
    });

    it("laesst die Breiten der anderen Abschnitte unberuehrt", () => {
      const state: SectionState = { ...base(), spans: { weather: SPAN_HALF } };
      expect(toggleSectionWidth(state, "messages").spans).toEqual({ weather: SPAN_HALF, messages: SPAN_HALF });
    });

    it("meldet die Flags eines Abschnitts", () => {
      const state: SectionState = { ...base(), hidden: ["homework"], spans: { weather: SPAN_HALF } };
      expect(sectionFlags(state, "messages", 0)).toEqual({ off: false, wide: true, first: true, last: false });
      expect(sectionFlags(state, "homework", 1)).toEqual({ off: true, wide: true, first: false, last: false });
      expect(sectionFlags(state, "weather", 2)).toEqual({ off: false, wide: false, first: false, last: true });
    });
  });
});
