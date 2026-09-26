import { MissingDataError, RequestError } from "./errors";
import { EdupageSession } from "./session";
import { encodeFormData } from "./protocol";

export const GERMAN_WEEKDAYS = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"];

export interface ParsedLesson {
  period: number | null;
  startTime: string | null;
  endTime: string | null;
  subject: string;
  teachers: string[];
  classrooms: string[];
  curriculum: string | null;
  onlineLink: string | null;
  isCancelled: boolean;
  isEvent: boolean;
}

export interface LessonDict {
  period: string;
  time: string;
  title: string;
  is_lernzeit: boolean;
  teachers: string;
  rooms: string;
  is_cancelled: boolean;
  is_event: boolean;
  is_online: boolean;
  row_period?: string;
  rowspan?: number;
}

/** Tagesplan laden (Port von `__get_date_plan`, Paket N-D). */
export async function fetchDayPlan(session: EdupageSession, subdomain: string, userId: string, date: string): Promise<unknown[]> {
  const host = subdomain.includes(".") ? subdomain.toLowerCase() : `${subdomain.toLowerCase()}.edupage.org`;
  const csrfPage = await session.get(`https://${host}/dashboard/eb.php?mode=ttday`);
  const gpid = csrfPage.text.split("gpid=")[1]?.split("&")[0];
  const gsh = csrfPage.text.split("gsh=")[1]?.split('"')[0];
  if (!gpid || !gsh) throw new MissingDataError("missing gpid/gsh for timetable");
  const nextGpid = String(Number.parseInt(gpid, 10) + 1);
  const body = encodeFormData({ gpid: nextGpid, gsh, action: "loadData", user: userId, changes: "{}", date, dateto: date, _LJSL: "4096" });
  const raw = await session.postRaw(`https://${host}/gcall`, body);
  const startMarker = `${userId}",`;
  const after = raw.text.split(startMarker)[1];
  const cut = after !== undefined ? after.lastIndexOf(",[") : -1;
  const middle = cut >= 0 ? after?.slice(0, cut) : undefined;
  if (middle === undefined) throw new MissingDataError("unexpected gcall response");
  let data: Record<string, unknown>;
  try {
    data = JSON.parse(middle) as Record<string, unknown>;
  } catch {
    throw new RequestError("Unerwartete Antwort von EduPage.");
  }
  const dates = (data.dates ?? {}) as Record<string, { plan?: unknown[] }>;
  const plan = dates[date]?.plan;
  if (!Array.isArray(plan)) throw new MissingDataError("no day plan in response");
  return plan;
}

interface DbiMaps {
  subjects: Record<string, { short?: string }>;
  teachers: Record<string, { firstname?: string; lastname?: string }>;
  classrooms: Record<string, { short?: string }>;
}

const fullName = (person?: { firstname?: string; lastname?: string }): string =>
  `${person?.firstname ?? ""} ${person?.lastname ?? ""}`.trim();

/** Tagesplan parsen (Port von `__parse_timetable`, nur Anzeige-relevantes). */
export function parseDayPlan(plan: unknown[], dbi: Partial<DbiMaps>): ParsedLesson[] {
  const lessons: ParsedLesson[] = [];
  for (const raw of plan) {
    if (typeof raw !== "object" || raw === null) continue;
    const lesson = raw as Record<string, unknown>;
    const header = lesson.header;
    if ("header" in lesson && (!header || (Array.isArray(header) && (header.length === 0 || (header[0] as Record<string, unknown>)?.cmd === "addlesson_t")))) continue;
    const periodRaw = lesson.uniperiod;
    const period = typeof periodRaw === "string" && /^\d+$/.test(periodRaw) ? Number.parseInt(periodRaw, 10) : null;
    const clock = (value: unknown): string | null => {
      if (typeof value !== "string" || !value) return null;
      const fixed = value.replace("24:00", "23:59");
      return /^\d{2}:\d{2}/.test(fixed) ? fixed.slice(0, 5) : null;
    };
    const subjectId = lesson.subjectid;
    const subjectName = (subjectId !== undefined && subjectId !== null ? dbi.subjects?.[String(subjectId)]?.short : undefined) ?? "";
    const teacherIds = Array.isArray(lesson.teacherids) ? lesson.teacherids : [];
    const teachers = teacherIds
      .map((id) => fullName(dbi.teachers?.[String(id)]))
      .filter((name) => name);
    const roomIds = Array.isArray(lesson.classroomids) ? lesson.classroomids : [];
    const classrooms = roomIds
      .map((id) => dbi.classrooms?.[String(id)]?.short ?? "")
      .filter((name) => name);
    const flags = (typeof lesson.flags === "object" && lesson.flags !== null ? lesson.flags : {}) as Record<string, Record<string, string>>;
    const curriculum = flags.dp0?.note_wd || flags.event?.name || null;
    const type = typeof lesson.type === "string" ? lesson.type : "";
    lessons.push({
      period,
      startTime: clock(lesson.starttime),
      endTime: clock(lesson.endtime),
      subject: subjectName.trim(),
      teachers,
      classrooms,
      curriculum: curriculum?.trim() || null,
      onlineLink: typeof lesson.ol_url === "string" ? lesson.ol_url : null,
      isCancelled: Boolean(lesson.removed) || type === "absent" || type === "",
      isEvent: type === "event" || type === "out" || Boolean(lesson.main),
    });
  }
  return lessons;
}

/** Lesson → Anzeige-Dict (Port von `lesson_to_dict`). */
export function lessonToDict(lesson: ParsedLesson): LessonDict {
  const clock = (value: string | null): string => value ?? "–";
  const title = lesson.subject || lesson.curriculum || "–";
  return {
    period: lesson.period !== null ? String(lesson.period) : "–",
    time: `${clock(lesson.startTime)}–${clock(lesson.endTime)}`,
    title,
    is_lernzeit: title.toLowerCase().includes("lernzeit"),
    teachers: lesson.teachers.join(", "),
    rooms: lesson.classrooms.join(", "),
    is_cancelled: lesson.isCancelled,
    is_event: lesson.isEvent,
    is_online: lesson.onlineLink !== null,
  };
}

const periodNum = (item: LessonDict): number | null => {
  const num = Number.parseInt(item.period, 10);
  return Number.isInteger(num) ? num : null;
};

/** Ganztägiges Event (Port von `_is_allday_event`). */
export function isAlldayEvent(item: LessonDict): boolean {
  return item.is_event && periodNum(item) === null;
}

/** Lernzeit-Blöcke verbinden (Port von `merge_lernzeit`). */
export function mergeLernzeit(items: LessonDict[]): LessonDict[] {
  const out: LessonDict[] = [];
  let index = 0;
  while (index < items.length) {
    const current = items[index];
    if (!current || !current.title.toLowerCase().includes("lernzeit")) {
      if (current) out.push(current);
      index += 1;
      continue;
    }
    const group = [current];
    let next = index + 1;
    while (next < items.length) {
      const candidate = items[next];
      if (!candidate || !candidate.title.toLowerCase().includes("lernzeit")) break;
      const prevNum = periodNum(group[group.length - 1] as LessonDict);
      const curNum = periodNum(candidate);
      if (prevNum !== null && curNum !== null && curNum !== prevNum + 1) break;
      group.push(candidate);
      next += 1;
    }
    if (group.length > 1) {
      const first = group[0] as LessonDict;
      const last = group[group.length - 1] as LessonDict;
      const union = (key: "teachers" | "rooms"): string => {
        const seen: string[] = [];
        for (const entry of group) {
          for (const part of entry[key].split(",")) {
            const trimmed = part.trim();
            if (trimmed && !seen.includes(trimmed)) seen.push(trimmed);
          }
        }
        return seen.join(", ");
      };
      const merged: LessonDict = { ...first };
      if (first.period !== "–" && last.period !== "–") merged.period = `${first.period}–${last.period}`;
      merged.time = `${first.time.split("–")[0]}–${last.time.split("–").slice(-1)[0]}`;
      merged.teachers = union("teachers");
      merged.rooms = union("rooms");
      merged.is_cancelled = group.every((entry) => entry.is_cancelled);
      merged.is_event = group.some((entry) => entry.is_event);
      merged.is_online = group.some((entry) => entry.is_online);
      merged.row_period = first.period;
      merged.rowspan = group.length;
      out.push(merged);
      index = next;
      continue;
    }
    out.push(current);
    index += 1;
  }
  for (const entry of out) {
    entry.row_period = entry.row_period ?? entry.period;
    entry.rowspan = entry.rowspan ?? 1;
  }
  return out;
}
