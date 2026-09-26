import { RequestError } from "./errors";
import { parseServerDate } from "./serializers";
import { EdupageSession } from "./session";

export interface ParsedGrade {
  eventId: number;
  title: string;
  gradeN: number | string;
  comment: string | null;
  date: Date;
  subjectId: number;
  subjectName: string;
  teacherName: string;
  maxPoints: number | null;
  moreDetails: string[] | null;
  importance: number | null;
  verbal: boolean;
  percent: number | null;
  classAvg: number | null;
}

/** Notenseite laden (Port von `__get_grade_data`, Paket N-E). */
export async function fetchGradeData(session: EdupageSession, subdomain: string): Promise<Record<string, unknown>> {
  const host = subdomain.includes(".") ? subdomain.toLowerCase() : `${subdomain.toLowerCase()}.edupage.org`;
  const page = await session.get(`https://${host}/znamky/`);
  const middle = page.text.split(".znamkyStudentViewer(")[1]?.split(");\r\n\t\t});\r\n\t\t</script>")[0];
  if (middle === undefined) throw new RequestError("Unerwartete Antwort von EduPage.");
  try {
    return JSON.parse(middle) as Record<string, unknown>;
  } catch {
    throw new RequestError("Unerwartete Antwort von EduPage.");
  }
}

interface DbiSubjects {
  subjects?: Record<string, { short?: string }>;
  teachers?: Record<string, { firstname?: string; lastname?: string }>;
}

/** Noten parsen (Port von `Grades.get_grades` ohne Term). */
export function parseGrades(data: Record<string, unknown>, dbi: DbiSubjects): ParsedGrade[] {
  const grades = Array.isArray(data.vsetkyZnamky) ? data.vsetkyZnamky : [];
  const details = ((data.vsetkyUdalosti ?? {}) as Record<string, unknown>).edupage;
  const detailMap = (typeof details === "object" && details !== null ? details : {}) as Record<string, Record<string, unknown>>;
  const out: ParsedGrade[] = [];
  for (const raw of grades) {
    if (typeof raw !== "object" || raw === null) continue;
    const grade = raw as Record<string, unknown>;
    const idRaw = grade.udalostid;
    if (idRaw === undefined || idRaw === null || idRaw === "") continue;
    const eventId = Number.parseInt(String(idRaw), 10);
    if (!Number.isInteger(eventId)) continue;
    const detail = detailMap[String(idRaw)] ?? {};
    const title = typeof detail.p_meno === "string" ? detail.p_meno : "";
    const date = parseServerDate(typeof grade.datum === "string" ? grade.datum : "");
    const subjectRaw = detail.PredmetID;
    if (subjectRaw === undefined || subjectRaw === null || subjectRaw === "vsetky") continue;
    const subjectId = Number.parseInt(String(subjectRaw), 10);
    const subjectName = dbi.subjects?.[String(subjectRaw)]?.short ?? "";
    const teacherRaw = detail.UcitelID;
    let teacherName = "";
    if (teacherRaw !== undefined && teacherRaw !== null) {
      const person = dbi.teachers?.[String(teacherRaw)];
      if (person) teacherName = `${person.firstname ?? ""} ${person.lastname ?? ""}`.trim();
    }
    const gradeType = detail.p_typ_udalosti;
    let maxPoints: number | null = null;
    let importance: number | null = null;
    if (gradeType === "1") {
      importance = Number.parseFloat(String(detail.p_vaha)) / 20;
    } else if (gradeType === "2") {
      maxPoints = Number.parseFloat(String(detail.p_vaha));
      importance = null;
    } else if (gradeType === "3") {
      maxPoints = Number.parseFloat(String(detail.p_vaha_body));
      importance = Number.parseFloat(String(detail.p_vaha)) / 20;
    }
    const moreRaw = detail.moredata;
    const moreDetails = Array.isArray(moreRaw) ? moreRaw.map(String) : moreRaw === undefined || moreRaw === null ? null : [String(moreRaw)];
    const dataRaw = typeof grade.data === "string" ? grade.data : "";
    const parts = dataRaw.split(" (", 2);
    const first = parts[0] ?? "";
    const gradeN: number | string = /^\d+$/.test(first) ? Number.parseFloat(first) : first;
    let comment: string | null = null;
    if (parts.length > 1) {
      const rest = parts.slice(1).join(" (");
      comment = rest.slice(0, rest.lastIndexOf(")")) || null;
    }
    let verbal = false;
    let percent: number | null = null;
    try {
      const numeric = Number(gradeN);
      if (!Number.isFinite(numeric)) throw new Error("verbal");
      if (maxPoints) percent = Math.round((numeric / maxPoints) * 100 * 100) / 100;
      else if (maxPoints === 0) percent = Number.POSITIVE_INFINITY;
      else percent = null;
    } catch {
      verbal = true;
    }
    const priemer = detail.priemer;
    out.push({
      eventId, title, gradeN, comment, date, subjectId,
      subjectName: typeof subjectName === "string" ? subjectName : "",
      teacherName, maxPoints, moreDetails, importance, verbal, percent,
      classAvg: priemer === undefined || priemer === null ? null : Number.parseFloat(String(priemer)),
    });
  }
  return out;
}

const deNum = (value: number): string => {
  let text = String(value);
  if (text.includes("e") || text.includes("E")) text = String(Number(value.toPrecision(12)));
  if (text.includes(".")) text = text.replace(/0+$/, "").replace(/\.$/, "");
  return text.replace(".", ",");
};

/** EduGrade → Dict (Port von `grade_to_dict`). */
export function gradeToDict(grade: ParsedGrade): Record<string, unknown> {
  const raw = grade.gradeN;
  let numeric: number | null = null;
  if (typeof raw === "number") numeric = raw;
  else if (typeof raw === "string" && raw.trim()) {
    const parsed = Number.parseFloat(raw.trim().replace(",", "."));
    numeric = Number.isFinite(parsed) ? parsed : null;
  }
  if (numeric !== null && !(numeric >= 1 && numeric <= 6)) numeric = null;
  const isClassic = numeric !== null && !grade.verbal;
  let display: string;
  if (isClassic && numeric !== null) display = deNum(numeric);
  else if (typeof raw === "number" && Number.isInteger(raw)) display = String(raw);
  else if (typeof raw === "number") display = deNum(raw);
  else if (typeof raw === "string" && raw.trim()) display = raw.trim();
  else display = "–";
  let weight = Number(grade.importance ?? 1.0);
  if (!Number.isFinite(weight) || weight <= 0) weight = 1.0;
  const maxPoints = grade.maxPoints !== null && Number.isFinite(grade.maxPoints) ? grade.maxPoints : null;
  const percent = grade.percent !== null && Number.isFinite(grade.percent) ? grade.percent : null;
  const classAvg = grade.classAvg !== null && Number.isFinite(grade.classAvg) ? grade.classAvg : null;
  const pad = (value: number): string => String(value).padStart(2, "0");
  const sub: string[] = [];
  if (maxPoints !== null) sub.push(`von ${deNum(maxPoints)} Punkten`);
  if (percent !== null) sub.push(`${deNum(percent)} %`);
  if (weight !== 1.0) sub.push(`Gewichtung ×${deNum(weight)}`);
  let badge = "gx";
  if (isClassic && numeric !== null) badge = numeric <= 2 ? "g12" : numeric <= 3 ? "g3" : numeric <= 4 ? "g4" : "g56";
  return {
    id: grade.eventId,
    title: grade.title.trim() || "Note",
    subject: grade.subjectName.trim() || "Sonstiges",
    teacher: grade.teacherName,
    date_display: `${pad(grade.date.getDate())}.${pad(grade.date.getMonth() + 1)}.${grade.date.getFullYear()}`,
    date_iso: `${grade.date.getFullYear()}-${pad(grade.date.getMonth() + 1)}-${pad(grade.date.getDate())}`,
    sort_key: `${grade.date.getFullYear()}-${pad(grade.date.getMonth() + 1)}-${pad(grade.date.getDate())}T${pad(grade.date.getHours())}:${pad(grade.date.getMinutes())}:${pad(grade.date.getSeconds())}`,
    comment: (grade.comment ?? "").trim(),
    grade_display: display,
    grade_num: isClassic ? numeric : null,
    weight,
    weight_display: weight === 1.0 ? "" : `×${deNum(weight)}`,
    grade_sub: sub.join(" · "),
    badge,
    class_avg: classAvg,
    class_avg_display: classAvg !== null ? deNum(classAvg) : "",
    is_classic: isClassic,
  };
}
