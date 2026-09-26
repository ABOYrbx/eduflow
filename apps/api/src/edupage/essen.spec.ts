import { candidateUrls, parseMenuPdf, parseMenuText, splitDishes, weekKey } from "./essen";

const MENU_TEXT = [
  "Speisekarte Montag 14.9. bis Freitag 18.9.2026",
  "Montag: Tomatensuppe 3,50 € Schnitzel mit Pommes 7,90 €",
  "Dienstag: V ollkornnudeln mit Soße 5,20 €",
  "Mittwoch: DGE-Empfehlung frisch und gesund zubereitet ohne Preisangabe hier",
  "Donnerstag: Fisch 6,80 €",
  "Freitag: Eintopf 4,90 €",
].join("\n");

describe("essen (Port von essen.py, Paket N-G)", () => {
  it("berechnet ISO-Wochen wie Python", () => {
    const vectors: Array<[string, string]> = [
      ["2026-09-16", "2026-W38"],
      ["2026-01-01", "2026-W01"],
      ["2025-12-29", "2026-W01"],
      ["2025-12-31", "2026-W01"],
      ["2026-12-28", "2026-W53"],
      ["2027-01-03", "2026-W53"],
      ["2024-12-30", "2025-W01"],
      ["2025-01-01", "2025-W01"],
    ];
    for (const [input, expected] of vectors) {
      const [year, month, day] = input.split("-").map(Number);
      expect(weekKey(new Date(year ?? 0, (month ?? 1) - 1, day))).toBe(expected);
    }
  });

  it("baut PDF-URL-Kandidaten wie Python", () => {
    const urls = candidateUrls("https://www.sws-schulen.de", 2026, 38);
    expect(urls).toHaveLength(2);
    expect(urls[0]).toBe("https://www.sws-schulen.de/wp-content/uploads/2026/09/Mensa-und-Ausser-Haus-38.-KW.pdf");
    expect(urls).toContain("https://www.sws-schulen.de/wp-content/uploads/2026/08/Mensa-und-Ausser-Haus-38.-KW.pdf");
    const single = candidateUrls("https://www.sws-schulen.de", 2026, 5);
    expect(single.some((url) => url.includes("Mensa-und-Ausser-Haus-5.-KW.pdf"))).toBe(true);
    expect(single.some((url) => url.includes("Mensa-und-Ausser-Haus-05.-KW.pdf"))).toBe(true);
  });

  it("teilt Gerichte und Hinweise wie split_dishes", () => {
    expect(splitDishes("Schnitzel 7,90 € Pommes 2,50 €")).toEqual({
      dishes: [{ text: "Schnitzel", price: "7,90 €" }, { text: "Pommes", price: "2,50 €" }],
      note: "",
    });
    expect(splitDishes("Nur ein langer Hinweistext ohne Preis der über dreißig Zeichen lang ist")).toEqual({
      dishes: [{ text: "Nur ein langer Hinweistext ohne Preis der über dreißig Zeichen lang ist", price: "" }],
      note: "",
    });
  });

  it("parst Wochenlabel und Tage wie parse_menu_text", () => {
    const { days, label } = parseMenuText(MENU_TEXT);
    expect(label).toBe("14.9. – 18.9.2026");
    expect(days.Montag?.dishes).toEqual([{ text: "Tomatensuppe", price: "3,50 €" }, { text: "Schnitzel mit Pommes", price: "7,90 €" }]);
    expect(days.Dienstag?.dishes).toEqual([{ text: "Vollkornnudeln mit Soße", price: "5,20 €" }]);
  });

  it("baut das Anzeige-Dict wie parse_pdf", async () => {
    const menu = await parseMenuPdf(Buffer.from("pdf"), 2026, 38, async () => MENU_TEXT, new Date(2026, 8, 16, 12, 0, 0));
    expect(menu.week).toBe("2026-W38");
    expect(menu.label).toBe("14.9. – 18.9.2026");
    expect(menu.days.Montag?.date).toBe("2026-09-14");
    expect(menu.days.Freitag?.dishes).toEqual([{ text: "Eintopf", price: "4,90 €" }]);
    expect(menu.today).toBe("Mittwoch");
    await expect(parseMenuPdf(Buffer.from("pdf"), 2026, 38, async () => "kurz")).rejects.toThrow("keinen lesbaren Text");
    await expect(parseMenuPdf(Buffer.from("pdf"), 2026, 38, async () => "x".repeat(60))).rejects.toThrow("keine Wochentage");
  });
});
