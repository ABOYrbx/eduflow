import { changeToDict, fetchSubstitutionHtml, parseSubstitutionHtml, resolveUserClass } from "./school";
import { ExpiredSessionError } from "./errors";
import { EdupageSession, FetchImpl } from "./session";

const SECTION = (cls: string, rows: string): string =>
  `</div><div class="section print-nobreak"><div class="header"><span class="print-font-resizable">${cls}</span><div class="rows">${rows}</div></div>`;
const ROW = (cls: string, period: string, info: string): string =>
  `<div class="row ${cls}"><div class="period"><span class="print-font-resizable">${period}</span></div><div class="info"><span class="print-font-resizable">${info}</span></div></div>`;
const FOOTER = '<div style="text-align:center;font-size:12px"><a href="https://www.asctimetables.com" target="_blank">www.asctimetables.com</a> - foot';

const HTML = `<div><span class="print-font-resizable">X</span>`
  + SECTION("1. A", ROW("change", "1.", "Mathe - Suplování") + ROW("remove", "2 - 3", "Physik") + ROW("event", "18:00 - 19:00", '<img src="/global/pics/ui/events_32.svg" style="height:16px;"/>Elternabend'))
  + SECTION("1. D", ROW("nosubst", "", "Na tento den není žádné suplování."))
  + FOOTER;

function stubPostJson(data: unknown): FetchImpl {
  return async () => ({
    status: 200, url: "https://demo.edupage.org/substitution/server/viewer.js?__func=getSubstViewerDayDataHtml",
    headers: { get: () => null }, text: async () => JSON.stringify(data), arrayBuffer: async () => new ArrayBuffer(0),
  });
}

describe("school-Protokoll (Port von substitution.py + api/school.py, N-H)", () => {
  it("lädt Viewer-HTML und erkennt abgelaufene Sitzungen", async () => {
    const html = await fetchSubstitutionHtml(new EdupageSession(stubPostJson({ r: "<div>ok</div>" })), "demo", "gsh", "2026-09-21");
    expect(html).toBe("<div>ok</div>");
    await expect(fetchSubstitutionHtml(new EdupageSession(stubPostJson({ reload: true })), "demo", "gsh", "2026-09-21")).rejects.toBeInstanceOf(ExpiredSessionError);
  });

  it("parst echte Markup-Formen wie Python", () => {
    const changes = parseSubstitutionHtml(HTML);
    expect(changes).toHaveLength(4);
    expect(changes?.map(changeToDict)).toEqual([
      { class: "1. A", lesson: "1", title: "Mathe - Suplování", action: "change" },
      { class: "1. A", lesson: "2–3", title: "Physik", action: "remove" },
      { class: "1. A", lesson: "1800–1900", title: "Elternabend", action: "" },
      { class: "1. D", lesson: "None", title: "Na tento den není žádné suplování.", action: "" },
    ]);
    expect(parseSubstitutionHtml("<div>leer</div>")).toBeNull();
  });

  it("löst die Klasse des Schülers aus dbi", () => {
    const dbi = { students: { 42: { classid: 7 } }, classes: { 7: { name: "5A" } } };
    expect(resolveUserClass(dbi, "42")).toBe("5A");
    expect(resolveUserClass(dbi, "Student42")).toBe("");
    expect(resolveUserClass({}, "42")).toBe("");
  });
});
