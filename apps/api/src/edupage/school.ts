import { ExpiredSessionError, MissingDataError, RequestError } from "./errors";
import { EdupageSession } from "./session";

export type SubstitutionAction = "add" | "change" | "remove";

export interface TimetableChange {
  changeClass: string;
  lesson: number | [number | null, number | null] | null;
  title: string;
  action: SubstitutionAction | null;
}

export interface ChangeDict { class: string; lesson: string; title: string; action: string; }

/** Python-`split(sep, maxsplit)` (Rest bleibt im letzten Teil). */
function splitMax(text: string, sep: string, maxsplit: number): string[] {
  const parts = text.split(sep);
  if (parts.length <= maxsplit + 1) return parts;
  return [...parts.slice(0, maxsplit), parts.slice(maxsplit).join(sep)];
}

const replaceAll = (text: string, search: string, replacement: string): string => text.split(search).join(replacement);

const parseIntDigits = (value: string): number | null => {
  const digits = value.replace(/[^0-9]/g, "");
  return digits ? Number.parseInt(digits, 10) : null;
};

const parseAction = (value: string): SubstitutionAction | null =>
  value === "add" ? "add" : value === "change" ? "change" : value === "remove" ? "remove" : null;

/** Vertretungs-HTML laden (Port von `__get_substitution_data`, Paket N-H). */
export async function fetchSubstitutionHtml(session: EdupageSession, subdomain: string, gsecHash: string, date: string): Promise<string> {
  const host = subdomain.includes(".") ? subdomain.toLowerCase() : `${subdomain.toLowerCase()}.edupage.org`;
  const response = await session.postJson(
    `https://${host}/substitution/server/viewer.js?__func=getSubstViewerDayDataHtml`,
    { __args: [null, { date, mode: "classes" }], __gsh: gsecHash },
  );
  const data = (typeof response.data === "object" && response.data !== null ? response.data : {}) as Record<string, unknown>;
  if (data.reload) throw new ExpiredSessionError("Invalid gsec hash! (Expired session, try logging in again!)");
  if (typeof data.r !== "string") throw new MissingDataError("missing substitution html");
  return data.r;
}

/** Vertretungs-HTML parsen (Port von `get_timetable_changes`). */
export function parseSubstitutionHtml(html: string): TimetableChange[] | null {
  const classDelim = '</div><div class="section print-nobreak"><div class="header"><span class="print-font-resizable">';
  const sections = html.split(classDelim).slice(1);
  if (!sections.length) return null;
  const footerDelim = '<div style="text-align:center;font-size:12px"><a href="https://www.asctimetables.com" target="_blank">www.asctimetables.com</a> -';
  const last = sections[sections.length - 1] ?? "";
  sections[sections.length - 1] = last.split(footerDelim)[0] ?? "";
  const cleaned = sections.map((section) => replaceAll(replaceAll(replaceAll(replaceAll(section,
    "</div>", ""), '<div class="period">', ""), '<span class="print-font-resizable">', ""), '<div class="info">', ""));
  const out: TimetableChange[] = [];
  for (const section of cleaned) {
    const parts = section.split("</span><div class=\"rows\">");
    if (parts.length < 2) throw new RequestError("unexpected substitution markup");
    const changeClass = parts[0] ?? "";
    const rows = (parts[1] ?? "").split('<div class="row ').slice(1);
    for (const row of rows) {
      const pieces = splitMax(replaceAll(row, '">', "</span>"), "</span>", 3).slice(0, -1);
      if (pieces.length !== 3) throw new RequestError("unexpected substitution row");
      const [actionRaw = "", lessonRaw = "", titleRaw = ""] = pieces;
      let title = titleRaw;
      if (title.includes("<img src=")) title = title.split(">")[1] ?? "";
      const action = parseAction(actionRaw);
      let lesson: number | [number | null, number | null] | null;
      if (lessonRaw.includes("-")) {
        const range = lessonRaw.split(" - ");
        if (range.length !== 2) throw new RequestError("unexpected lesson range");
        lesson = [parseIntDigits(range[0] ?? ""), parseIntDigits(range[1] ?? "")];
      } else {
        lesson = parseIntDigits(lessonRaw);
      }
      out.push({ changeClass, lesson, title, action });
    }
  }
  return out;
}

/** Change → API-Dict (Port von `_change_dict`). */
export function changeToDict(change: TimetableChange): ChangeDict {
  const lesson = Array.isArray(change.lesson)
    ? change.lesson.map((part) => (part === null ? "None" : String(part))).join("–")
    : change.lesson === null ? "None" : String(change.lesson);
  return {
    class: String(change.changeClass || ""),
    lesson,
    title: String(change.title || ""),
    action: String(change.action || ""),
  };
}

interface DbiLike {
  students?: Record<string, { classid?: unknown }>;
  classes?: Record<string, { name?: unknown; id?: unknown }>;
}

/** Klasse des Schülers aus dbi auflösen (Port von `build_substitutions`). */
export function resolveUserClass(dbi: unknown, userId: unknown): string {
  try {
    const record = (typeof dbi === "object" && dbi !== null ? dbi : {}) as DbiLike;
    const numericId = Number.parseInt(String(userId ?? ""), 10);
    if (!Number.isInteger(numericId)) return "";
    const classId = record.students?.[String(numericId)]?.classid;
    if (classId === undefined || classId === null) return "";
    const classes = record.classes ?? {};
    for (const [key, entry] of Object.entries(classes)) {
      if (Number.parseInt(key, 10) === Number(classId) || String((entry as { id?: unknown }).id ?? "") === String(classId)) {
        return String((entry as { name?: unknown }).name ?? "");
      }
    }
  } catch {
    /* best-effort wie Python */
  }
  return "";
}
