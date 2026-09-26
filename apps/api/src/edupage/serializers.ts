import type { TimelineEvent } from "./timeline";

/** Serializer-Parität zu `app.py` (Paket N-B): deutsche Labels, Zeitstempel,
 *  Anhangsuche, Like-Aufschlüsselung. Quellsprache ist Deutsch.
 */
export const TYPE_LABELS: Record<string, string> = {
  sprava: "Nachricht", chat: "Chat", anketa: "Umfrage", news: "Neuigkeit", genotif: "Mitteilung",
  homework: "Hausaufgabe", etesthw: "Online-Test", homeworkstudentstav: "Hausaufgaben-Status",
  bexam: "Schularbeit", sexam: "Test", oexam: "Mündliche Prüfung", pexam: "Projektprüfung",
  rexam: "Wiederholungsprüfung", testing: "Testung", testpridelenie: "Prüfungszuweisung",
  testvysledok: "Prüfungsergebnis", znamka: "Note", znamkydoc: "Notendokument",
  other_cb: "Klassenbucheintrag", ctevent: "Klassenereignis", bmeeting: "Besprechung",
  culture: "Kulturveranstaltung", event: "Ereignis", excursion: "Exkursion",
  parentsevening: "Elternabend", process: "Vorgang", schoolevent: "Schulveranstaltung",
  trip: "Ausflug", signin: "Anmeldung", meeting: "Versammlung", freeday: "Freier Tag",
  holiday: "Feiertag", sholiday: "Schulferien", ttcancel: "Entfallene Stunde",
  ctlesson: "Klassenlehrerstunde", distant: "Distanzunterricht", lesson: "Unterricht",
  project: "Projekt", plesson: "Geplante Stunde", other_safety: "Sicherheitshinweis",
  rlesson: "Wiederholungsstunde", timetable: "Stundenplan", bookroom: "Raumbuchung",
  changeroom: "Raumwechsel", substitution: "Vertretung", pipnutie: "Anstupser",
  ospravedlnenka: "Entschuldigung", representation: "Repräsentation", student_absent: "Fehlzeit",
  strava_kredit: "Essensguthaben", strava_vydaj: "Essensausgabe", stravamenu: "Speiseplan",
  h_stravamenu: "Speiseplan (Verlauf)", confirmation: "Bestätigung", contest: "Wettbewerb",
  album: "Fotoalbum", payments: "Zahlungen", lost: "Fundsache", vcelicka: "Bienchen", other: "Sonstiges",
};

const SK_DE_PHRASES: Array<[string, string]> = [
  ["Zverejnený nový rozvrh", "Neuer Stundenplan veröffentlicht"],
  ["Aktualizovaný fotoalbum", "Aktualisiertes Fotoalbum"],
  ["Nová ospravedlnenka", "Neue Entschuldigung"],
  ["Pridelený test", "Zugeteilter Test"],
  ["Udalosť:", "Ereignis:"],
  ["Známka", "Note"],
  ["Zverejneny novy rozvrh", "Neuer Stundenplan veröffentlicht"],
  ["Aktualizovany fotoalbum", "Aktualisiertes Fotoalbum"],
  ["Nova ospravedlnenka", "Neue Entschuldigung"],
  ["Prideleny test", "Zugeteilter Test"],
  ["Udalost:", "Ereignis:"],
  ["Znamka", "Note"],
];

const GERMAN_MONTHS = ["Januar", "Februar", "März", "April", "Mai", "Juni",
  "Juli", "August", "September", "Oktober", "November", "Dezember"];
const WEEKDAYS = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"];

/** Kleinschreibung + Umlaute-Toleranz (Port von `app._norm`). */
export function norm(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

/** `YYYY-MM-DD HH:MM:SS` strikt als Ortszeit parsen (Server-Format). */
export function parseServerDate(value: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/.exec(value);
  if (!match) throw new Error(`ungültiges Server-Datum: ${value}`);
  const [, year, month, day, hour, minute, second] = match.map(Number);
  return new Date(year ?? 0, (month ?? 1) - 1, day, hour, minute, second);
}

/** ISO ohne Zeitzone wie Python (`datetime.isoformat()` naiv). */
export function formatIsoLocal(date: Date): string {
  const pad = (value: number): string => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

/** Menschenlesbarer Zeitstempel (Port von `pretty_timestamp`, deutsch). */
export function prettyTimestamp(ts: Date, today = new Date()): string {
  const pad = (value: number): string => String(value).padStart(2, "0");
  const time = `${pad(ts.getHours())}:${pad(ts.getMinutes())}`;
  const startOfDay = (date: Date): Date => new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const delta = Math.round((startOfDay(today).getTime() - startOfDay(ts).getTime()) / 86400000);
  if (delta === 0) return `Heute · ${time}`;
  if (delta === 1) return `Gestern · ${time}`;
  if (delta > 1 && delta < 7) return `${WEEKDAYS[(ts.getDay() + 6) % 7]} · ${time}`;
  const month = GERMAN_MONTHS[ts.getMonth()] ?? "";
  if (ts.getFullYear() === today.getFullYear()) return `${ts.getDate()}. ${month} · ${time}`;
  return `${ts.getDate()}. ${month} ${ts.getFullYear()} · ${time}`;
}

/** Slowakische Server-Floskeln eindeutschen (Port von `translate_server_text`). */
export function translateServerText(text: string): string {
  if (!text) return text;
  let out = text;
  for (const [sk, de] of SK_DE_PHRASES) {
    if (out.includes(sk)) out = out.split(sk).join(de);
  }
  return out;
}

const ENTITY_MAP: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };

function unescapeHtml(value: string): string {
  return value
    .replace(/&#(\d+);/g, (_match, digits: string) => String.fromCharCode(Number.parseInt(digits, 10)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_match, hex: string) => String.fromCharCode(Number.parseInt(hex, 16)))
    .replace(/&(amp|lt|gt|quot|apos|nbsp);/g, (_match, name: string) => ENTITY_MAP[name] ?? _match);
}

/** HTML-Tags entfernen + Entities auflösen (Port von `_strip_html`). */
export function stripHtml(value: unknown): string {
  if (typeof value !== "string") return "";
  return unescapeHtml(value.replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();
}

export function formatPerson(value: string | null): string {
  return value === null ? "–" : value;
}

const ATTACH_NAME_KEYS = ["filename", "fileName", "name", "nazov", "nadpis", "subor", "originalName"];
const ATTACH_URL_KEYS = ["url", "file", "src", "href", "link", "downloadLink", "path"];
const ATTACH_SKIP_KEYS = ["avatar", "photo", "icon", "thumbnail", "image"];

export interface Attachment { name: string; url: string; }

/** Dateianhänge sammeln (Port von `extract_attachments`). */
export function extractAttachments(extra: unknown): Attachment[] {
  const found: Attachment[] = [];
  const seen = new Set<string>();
  const add = (name: unknown, url: unknown): void => {
    if (typeof url !== "string") return;
    const clean = url.trim();
    if (!clean || seen.has(clean)) return;
    if (!clean.startsWith("http://") && !clean.startsWith("https://") && !clean.startsWith("/")) return;
    let label = typeof name === "string" && name.trim() ? name.trim() : clean.split("/").pop() ?? "Datei";
    label = label.replace(/[\r\n"]/g, "").trim().slice(0, 120) || "Datei";
    seen.add(clean);
    found.push({ name: label, url: clean });
  };
  const walk = (node: unknown, depth: number): void => {
    if (node === null || node === undefined || depth > 6) return;
    if (Array.isArray(node)) {
      for (const item of node) walk(item, depth + 1);
      return;
    }
    if (typeof node === "object") {
      const record = node as Record<string, unknown>;
      let name: unknown = null;
      for (const key of ATTACH_NAME_KEYS) {
        const value = record[key];
        if (typeof value === "string" && value.trim()) { name = value.trim(); break; }
      }
      let url: unknown = null;
      for (const key of ATTACH_URL_KEYS) {
        const value = record[key];
        if (typeof value === "string" && value.trim()) {
          const trimmed = value.trim();
          if (trimmed.startsWith("http://") || trimmed.startsWith("https://") || trimmed.startsWith("/")) { url = trimmed; break; }
        }
      }
      if (typeof url === "string" && (typeof name === "string" || "file" in record || "url" in record)) {
        add(name ?? url.split("/").pop(), url);
      }
      for (const [key, value] of Object.entries(record)) {
        if (typeof key === "string" && ATTACH_SKIP_KEYS.some((skip) => key.toLowerCase().includes(skip))
          && (typeof value !== "object" || value === null)) continue;
        walk(value, depth + 1);
      }
      return;
    }
    if (typeof node === "string" && depth <= 2 && node.includes("<a ")) {
      for (const match of node.matchAll(/<a\s[^>]*href="([^"]+)"[^>]*>(.*?)<\/a>/gi)) {
        const href = (match[1] ?? "").trim();
        const label = stripHtml(match[2] ?? "");
        if (href.startsWith("http://") || href.startsWith("https://") || href.startsWith("/")) add(label || null, href);
      }
    }
  };
  try {
    walk(extra ?? {}, 0);
  } catch {
    /* best-effort wie Python */
  }
  return found;
}

/** TimelineEvent → API-Dict (Port von `event_to_dict`). */
export function eventToDict(event: TimelineEvent, today = new Date()): Record<string, unknown> {
  const tsIso = formatIsoLocal(event.timestamp);
  let text = event.text || "";
  const extra = event.additionalData ?? {};
  let extraJson = "";
  try {
    if (typeof extra === "object" && extra !== null) {
      extraJson = JSON.stringify(extra, null, 2);
      for (const key of ["messageContent", "text", "nazov", "name"]) {
        const candidate = (extra as Record<string, unknown>)[key];
        if (!text.trim() && typeof candidate === "string" && candidate.trim()) text = candidate;
      }
    } else {
      extraJson = extra ? String(extra) : "";
    }
  } catch {
    extraJson = "";
  }
  text = translateServerText(text);
  const typeValue = event.eventType ?? "unknown";
  return {
    id: event.eventId,
    timestamp: prettyTimestamp(event.timestamp, today),
    timestamp_iso: tsIso,
    sort_key: tsIso,
    author: formatPerson(event.author),
    recipient: formatPerson(event.recipient),
    type: typeValue,
    type_label: TYPE_LABELS[typeValue] ?? typeValue,
    text,
    is_starred: event.isStarred,
    is_done: event.isDone,
    reaction_count: event.reactionCount || 0,
    extra: extraJson,
    attachments: extractAttachments(extra),
  };
}

export function likerDisplayName(raw: unknown): string {
  if (typeof raw !== "string" || !raw.trim()) return "Unbekannt";
  const trimmed = raw.trim();
  if (trimmed.endsWith(")") && trimmed.includes(" (")) {
    const cut = trimmed.slice(0, trimmed.lastIndexOf(" (")).trim();
    return cut || "Unbekannt";
  }
  return trimmed || "Unbekannt";
}

export function fmtLikeDate(raw: unknown): string {
  if (typeof raw !== "string" || !raw.trim()) return "";
  const trimmed = raw.trim();
  try {
    const parsed = parseServerDate(trimmed);
    const pad = (value: number): string => String(value).padStart(2, "0");
    return `${pad(parsed.getDate())}.${pad(parsed.getMonth() + 1)}.${parsed.getFullYear()} ${pad(parsed.getHours())}:${pad(parsed.getMinutes())}`;
  } catch {
    return trimmed;
  }
}

function replyText(entry: Record<string, unknown>, edata: Record<string, unknown>): string {
  for (const key of ["messageContent", "text", "textReply"]) {
    const value = edata[key];
    if (typeof value === "string" && value.trim()) return stripHtml(value);
  }
  return stripHtml(entry.text);
}

export interface ThreadPayload {
  likes: Array<{ name: string; date: string }>;
  replies: Array<{ name: string; date: string; text: string }>;
  reply_ids: string[];
  summary: { total: number; likes: number; replies: number; seen: number };
  cached: boolean;
}

/** getRepliesItem-Antwort aufschlüsseln (Port von `parse_likes_response`). */
export function parseLikesResponse(data: unknown, rootId: number | string | null = null): Omit<ThreadPayload, "cached" | "reply_ids"> & { reply_ids: string[] } {
  let items: unknown[] = [];
  try {
    if (Array.isArray(data)) {
      items = data;
    } else if (typeof data === "object" && data !== null) {
      const record = data as Record<string, unknown>;
      const inner = record.data;
      if (typeof inner === "object" && inner !== null && !Array.isArray(inner)) {
        const innerRecord = inner as Record<string, unknown>;
        const list = innerRecord.reakcie ?? innerRecord.replies;
        items = Array.isArray(list) ? list : [];
      } else if (Array.isArray(inner)) {
        items = inner;
      } else {
        const list = record.reakcie ?? record.items;
        items = Array.isArray(list) ? list : [];
      }
    }
  } catch {
    items = [];
  }
  if (!Array.isArray(items)) items = [];
  const likes: Array<{ name: string; date: string }> = [];
  const replies: Array<{ name: string; date: string; text: string }> = [];
  let seen = 0;
  for (const entry of items) {
    try {
      if (typeof entry !== "object" || entry === null || Array.isArray(entry)) continue;
      const record = entry as Record<string, unknown>;
      if (record.pomocny_zaznam) continue;
      if (rootId !== null && String(record.timelineid) === String(rootId)) continue;
      let edata: Record<string, unknown> = {};
      const rawData = record.data;
      if (typeof rawData === "string") {
        try {
          const parsed: unknown = JSON.parse(rawData);
          if (typeof parsed === "object" && parsed !== null) edata = parsed as Record<string, unknown>;
        } catch {
          edata = {};
        }
      } else if (typeof rawData === "object" && rawData !== null) {
        edata = rawData as Record<string, unknown>;
      }
      if (edata.like) {
        likes.push({ name: likerDisplayName(record.vlastnik_meno), date: fmtLikeDate(edata.like) });
      } else if (record.typ === "confirmation") {
        seen += 1;
      } else {
        replies.push({ name: likerDisplayName(record.vlastnik_meno), date: fmtLikeDate(record.cas_pridania), text: replyText(record, edata) });
      }
    } catch {
      continue;
    }
  }
  return {
    likes,
    replies,
    reply_ids: [],
    summary: { total: likes.length + replies.length + seen, likes: likes.length, replies: replies.length, seen },
  };
}

export interface Recipient { id: string; name: string; kind: string; }

/** Empfänger aus Login-`dbi` (Port von `get_recipients`). */
export function recipientsFromDbi(dbi: unknown): Recipient[] {
  const out: Recipient[] = [];
  const seen = new Set<string>();
  const groups: Array<[unknown, "Lehrer" | "Schüler", string]> = (() => {
    const record = typeof dbi === "object" && dbi !== null ? (dbi as Record<string, unknown>) : {};
    return [[record.teachers, "Lehrer", "Teacher"], [record.students, "Schüler", "Student"]];
  })();
  for (const [group, kind, prefix] of groups) {
    if (typeof group !== "object" || group === null) continue;
    for (const [id, person] of Object.entries(group as Record<string, unknown>)) {
      if (!id || seen.has(`${prefix}${id}`)) continue;
      if (typeof person !== "object" || person === null) continue;
      const record = person as Record<string, unknown>;
      if (record.numberinclass === undefined || record.numberinclass === null) {
        if (record.classroomid === undefined || record.classroomid === null) continue;
      }
      const first = typeof record.firstname === "string" ? record.firstname : "";
      const last = typeof record.lastname === "string" ? record.lastname : "";
      const name = `${first} ${last}`.trim() || `${prefix}${id}`;
      seen.add(`${prefix}${id}`);
      out.push({ id: `${prefix}${id}`, name, kind });
    }
  }
  return out.sort((a, b) => {
    const left = a.name.toLowerCase();
    const right = b.name.toLowerCase();
    return left < right ? -1 : left > right ? 1 : 0;
  });
}
