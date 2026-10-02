import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from "@nestjs/common";
import { createHash, randomBytes } from "node:crypto";
import { Prisma } from "@prisma/client";
import { page as paginate, parsePage } from "../common/pagination";
import { PrismaService } from "../prisma/prisma.service";
import { t } from "../i18n";
import { AuthClaims } from "../auth/auth.service";
import { demoGrades, demoHomework, demoLessons, demoMessages, demoRecipients } from "../testing/demo-data";

const messageTypes = ["sprava", "news", "anketa", "chat", "genotif"];
const homeworkTypes = ["homework", "bexam", "sexam", "oexam", "pexam", "rexam", "testing", "etesthw", "testpridelenie"];
export interface SettingSpec { key: string; kind: string; label: string; options?: [string, string][]; default: unknown; min?: number; max?: number; section?: string; placeholder?: string; maxlength?: number; }
const settingsSchema: SettingSpec[] = [
  { key: "landing", kind: "select", label: t("settings.landingLabel"), options: [["uebersicht", t("settings.sectionUebersicht")], ["dashboard", t("settings.optDashboard")], ["hausaufgaben", t("settings.optHomework")], ["noten", t("settings.optGrades")], ["stundenplan", t("settings.optTimetable")]], default: "uebersicht" },
  { key: "hw_status", kind: "select", label: t("settings.hwStatusLabel"), options: [["alle", t("settings.optAll")], ["offen", t("settings.optOpen")], ["überfällig", t("settings.optOverdue")], ["erledigt", t("settings.optDone")], ["papierkorb", t("settings.optTrash")]], default: "alle" },
  { key: "hw_tests", kind: "bool", label: t("settings.hwTestsLabel"), default: false },
  { key: "time_format", kind: "select", label: t("settings.timeFormatLabel"), options: [["24h", t("settings.opt24h")], ["12h", t("settings.opt12h")]], default: "24h" },
  { key: "ov_unread", kind: "int", label: t("settings.ovUnreadLabel"), min: 1, max: 50, default: 10 },
  { key: "ov_homework", kind: "int", label: t("settings.ovHomeworkLabel"), min: 1, max: 50, default: 10 },
  { key: "ov_order", kind: "order", section: t("settings.sectionUebersicht"), label: t("settings.ovOrderLabel"), default: "messages,homework,weather" },
  { key: "ov_hidden", kind: "hidden", section: t("settings.sectionUebersicht"), label: t("settings.ovHiddenLabel"), default: "" },
  { key: "ov_span", kind: "span", section: t("settings.sectionUebersicht"), label: t("settings.ovSpanLabel"), default: "" },
  { key: "ov_wetter", kind: "bool", section: t("settings.sectionWetter"), label: t("settings.ovWetterLabel"), default: true },
  { key: "wetter_city", kind: "text", section: t("settings.sectionWetter"), label: t("settings.cityLabel"), placeholder: t("settings.cityPlaceholder"), maxlength: 100, default: "" },
];
const defaults: Record<string, unknown> = Object.fromEntries(settingsSchema.map((item) => [item.key, item.default]));
const hash = (text: string) => createHash("sha256").update(text).digest("hex");
const norm = (text: unknown) => typeof text === "string" ? text.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("en") : "";
const dateOnly = (value: string | Date) => new Date(value).toISOString().slice(0, 10);
const pad2 = (value: number): string => String(value).padStart(2, "0");
/** Wie `fmtLikeDate` im Echt-Provider (`edupage/serializers.ts`): TT.MM.JJJJ HH:MM. */
const threadDate = (value: string): string => {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return `${pad2(parsed.getDate())}.${pad2(parsed.getMonth() + 1)}.${parsed.getFullYear()} ${pad2(parsed.getHours())}:${pad2(parsed.getMinutes())}`;
};
const englishDays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const parseDate = (input: unknown, fallback: Date): Date => {
  if (input === undefined || input === "") return fallback;
  if (typeof input !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(input) || Number.isNaN(Date.parse(`${input}T00:00:00Z`))) throw new BadRequestException({ error: t("validation.dateFormatShort"), code: "VALIDATION" });
  const value = new Date(`${input}T00:00:00Z`);
  if (value.toISOString().slice(0, 10) !== input) throw new BadRequestException({ error: t("validation.dateFormatShort"), code: "VALIDATION" });
  return value;
};

@Injectable()
export class DemoSchoolService {
  private sentMessages = [...demoMessages];
  private readonly downloads = new Map<string, { accountId: string; id: number; idx: number; expires: number }>();

  constructor(private readonly prisma: PrismaService) {}

  assertEnabled(): void {
    if (process.env.EDUFLOW_PROVIDER !== "fake") throw new ForbiddenException({ error: t("auth.providerMissing"), code: "CONFIG_MISSING" });
  }

  private validatePage(query: Record<string, unknown>) {
    return parsePage(query);
  }

  private page<T>(items: T[], query: Record<string, unknown>) {
    return paginate(items, query);
  }

  private async allState(accountId: string, resource: string, stateKey: string) {
    const rows = await this.prisma.localResourceState.findMany({ where: { accountId, resource, stateKey } });
    return new Map(rows.map((row) => [row.resourceId, row.value]));
  }

  private async writeState(accountId: string, resource: string, resourceId: string, stateKey: string, value: unknown) {
    const where = { accountId_resource_resourceId_stateKey: { accountId, resource, resourceId, stateKey } };
    await this.prisma.localResourceState.upsert({ where, create: { accountId, resource, resourceId, stateKey, value: value as Prisma.InputJsonValue }, update: { value: value as Prisma.InputJsonValue } });
  }

  async messages(claims: AuthClaims, query: Record<string, unknown>) {
    this.assertEnabled();
    const since = parseDate(query.since, new Date("2000-01-01T00:00:00Z"));
    const type = typeof query.type === "string" ? query.type : "";
    if (type && !messageTypes.includes(type)) throw new BadRequestException({ error: t("messages.unknownType"), code: "VALIDATION" });
    const words = norm(typeof query.q === "string" ? query.q.slice(0, 200) : "").split(/\s+/).filter(Boolean);
    const items = this.sentMessages.filter((message) => {
      if (!messageTypes.includes(message.type) || message.additional_data.textReply) return false;
      if (type && message.type !== type) return false;
      if (new Date(message.timestamp_iso) < since) return false;
      const haystack = norm([message.author, message.recipient, message.text, message.type_label].join(" "));
      return words.every((word) => haystack.includes(word));
    }).sort((a, b) => b.sort_key.localeCompare(a.sort_key));
    return this.page(items, query);
  }

  private threadPayload(id: number) {
    const root = this.sentMessages.find((item) => item.id === id);
    if (!root) throw new NotFoundException({ error: t("messages.notFound"), code: "NOT_FOUND" });
    // Alle Antworten des Threads, nicht nur die erste: eine Demo-Nachricht
    // kann mehrere Antworten haben (siehe demoMessages, `textReply`).
    const replies = this.sentMessages.filter((item) => item.additional_data.textReply === String(id));
    const likes = [{ name: "Lea Beispiel", date: "25.09.2026 14:12" }];
    const seen = 1;
    return {
      likes,
      replies: replies.map((reply) => ({ name: reply.author, date: threadDate(reply.timestamp_iso), text: reply.text })),
      reply_ids: replies.map((reply) => String(reply.id)),
      summary: { total: likes.length + replies.length + seen, likes: likes.length, replies: replies.length, seen },
      cached: true,
    };
  }

  async thread(claims: AuthClaims, id: number) {
    this.assertEnabled();
    return this.threadPayload(id);
  }

  async markMessagesRead(claims: AuthClaims) {
    this.assertEnabled();
    const key = { accountId: claims.sub, resource: "messages", resourceId: "all", stateKey: "read" };
    const previous = await this.prisma.localResourceState.findUnique({ where: { accountId_resource_resourceId_stateKey: key } });
    await this.writeState(claims.sub, "messages", "all", "read", true);
    return { marked: previous?.value === true ? 0 : this.sentMessages.filter((item) => messageTypes.includes(item.type)).length };
  }

  recipients() { this.assertEnabled(); return this.page(demoRecipients, {}); }

  async sendMessage(body: unknown) {
    this.assertEnabled();
    if (typeof body !== "object" || body === null || Array.isArray(body)) throw new BadRequestException({ error: t("validation.jsonObject"), code: "VALIDATION" });
    const input = body as Record<string, unknown>;
    const recipients = Array.isArray(input.recipients) ? input.recipients.filter((item): item is string => typeof item === "string") : [];
    const text = typeof input.body === "string" ? input.body.trim() : "";
    if (!recipients.length || !text || recipients.some((id) => !demoRecipients.some((recipient) => recipient.id === id))) throw new BadRequestException({ error: t("messages.recipientsBody"), code: "VALIDATION" });
    const now = new Date(); const stamp = now.toISOString().slice(0, 19).replace("T", " ");
    const message = { id: 4999 + this.sentMessages.length, timestamp: stamp, timestamp_iso: now.toISOString(), sort_key: now.toISOString(), text, author: "Demo student", recipient: recipients.map((id) => demoRecipients.find((r) => r.id === id)?.name).join(", "), type: "sprava", type_label: "Message", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 0, created_at: now.toISOString(), is_removed: false };
    this.sentMessages.unshift(message);
    return message;
  }

  async reply(id: number, body: unknown) {
    this.assertEnabled();
    const root = this.sentMessages.find((item) => item.id === id);
    if (!root) throw new NotFoundException({ error: t("messages.notFound"), code: "NOT_FOUND" });
    const text = typeof body === "object" && body !== null && "body" in body && typeof (body as { body?: unknown }).body === "string" ? (body as { body: string }).body.trim() : "";
    if (!text) throw new BadRequestException({ error: t("messages.noReplyAlt"), code: "VALIDATION" });
    const now = new Date(); const stamp = now.toISOString().slice(0, 19).replace("T", " ");
    const reply = { id: 4999 + this.sentMessages.length, timestamp: stamp, timestamp_iso: now.toISOString(), sort_key: now.toISOString(), text, author: "Demo student", recipient: root.author, type: root.type, type_label: root.type_label, additional_data: { textReply: String(id) }, is_starred: false, is_done: false, done_at: "", reaction_count: 0, created_at: now.toISOString(), is_removed: false };
    this.sentMessages.push(reply);
    // Wie der Echt-Provider (edupage/data.ts): Thread frisch zurückgeben,
    // nicht das Nachrichten-Objekt (Web ignoriert den Body, Mac/Android
    // dekodieren ThreadResponse tolerant).
    return { ...this.threadPayload(id), cached: false };
  }

  async issueDownload(claims: AuthClaims, id: number, idx: number) {
    this.assertEnabled();
    const item = this.sentMessages.find((message) => message.id === id);
    if (!item || idx !== 0 || typeof item.additional_data.filename !== "string") throw new NotFoundException({ error: t("messages.attachment"), code: "NOT_FOUND" });
    const token = randomBytes(24).toString("hex");
    this.downloads.set(hash(token), { accountId: claims.sub, id, idx, expires: Date.now() + 5 * 60_000 });
    return { download_token: token, expires_in: 300 };
  }

  attachment(claims: AuthClaims | undefined, id: number, idx: number, token?: string) {
    this.assertEnabled();
    if (!claims && token) {
      const grant = this.downloads.get(hash(token));
      if (!grant || grant.expires < Date.now() || grant.id !== id || grant.idx !== idx) throw new NotFoundException({ error: t("messages.attachment"), code: "NOT_FOUND" });
      this.downloads.delete(hash(token));
      claims = { sub: grant.accountId, jti: "", tokenUse: "access" };
    }
    if (!claims) throw new NotFoundException({ error: t("messages.attachment"), code: "NOT_FOUND" });
    const item = this.sentMessages.find((message) => message.id === id);
    if (!item || idx !== 0 || typeof item.additional_data.filename !== "string") throw new NotFoundException({ error: t("messages.attachment"), code: "NOT_FOUND" });
    return { filename: item.additional_data.filename, content: Buffer.from("EduFlow demo: sample attachment\n", "utf8") };
  }

  async homework(claims: AuthClaims, query: Record<string, unknown>) {
    this.assertEnabled();
    const since = parseDate(query.since, new Date("2000-01-01T00:00:00Z"));
    const includeTests = query.include_tests === "1" || query.include_tests === "true";
    const doneState = await this.allState(claims.sub, "homework", "done");
    const trashState = await this.allState(claims.sub, "homework", "trash");
    let all = demoHomework.filter((item) => (includeTests || !homeworkTypes.slice(1).includes(item.type)) && new Date(`${item.assigned_iso}T00:00:00Z`) >= since).map((item) => {
      const done = doneState.has(String(item.id)) ? doneState.get(String(item.id)) === true : item.is_done;
      const hidden = trashState.get(String(item.id)) === true;
      const dueDate = item.due;
      const status = done ? "erledigt" : dueDate < dateOnly(new Date()) ? "überfällig" : dueDate === dateOnly(new Date()) ? "heute fällig" : "offen";
      return { ...item, is_done: done, is_hidden: hidden, status };
    });
    const counts = { offen: all.filter((item) => !item.is_hidden && ["offen", "heute fällig"].includes(item.status)).length, ueberfaellig: all.filter((item) => !item.is_hidden && item.status === "überfällig").length, erledigt: all.filter((item) => !item.is_hidden && item.status === "erledigt").length, papierkorb: all.filter((item) => item.is_hidden).length };
    const status = typeof query.status === "string" ? query.status : "alle";
    if (!["alle", "offen", "überfällig", "erledigt", "papierkorb"].includes(status)) throw new BadRequestException({ error: t("validation.status"), code: "VALIDATION" });
    const q = norm(typeof query.q === "string" ? query.q : "");
    all = all.filter((item) => {
      const hidden = item.is_hidden;
      if (status === "papierkorb" ? !hidden : status !== "alle" && hidden) return false;
      if (status === "offen" && !["offen", "heute fällig"].includes(item.status)) return false;
      if (status === "überfällig" && item.status !== "überfällig") return false;
      if (status === "erledigt" && item.status !== "erledigt") return false;
      return !q || norm([item.title, item.subject, item.description, item.teacher].join(" ")).includes(q);
    });
    const rank: Record<string, number> = { "überfällig": 0, "heute fällig": 1, offen: 2, erledigt: 3 };
    all.sort((a, b) => Number(a.is_hidden) - Number(b.is_hidden) || (rank[a.status] ?? 4) - (rank[b.status] ?? 4) || a.due.localeCompare(b.due));
    return { ...this.page(all, query), counts, cache_info: "Sample data" };
  }

  async homeworkChange(claims: AuthClaims, id: string, mode: "done" | "trash", body: unknown) {
    this.assertEnabled();
    const item = demoHomework.find((entry) => String(entry.id) === id);
    if (!item) throw new NotFoundException({ error: t("homework.notFound"), code: "NOT_FOUND" });
    const input = typeof body === "object" && body !== null ? body as Record<string, unknown> : {};
    if (mode === "done") {
      const done = typeof input.done === "boolean" ? input.done : true;
      await this.writeState(claims.sub, "homework", id, "done", done);
      if (!done) await this.writeState(claims.sub, "homework", id, "trash", false);
      return { ...item, is_done: done, is_hidden: false, status: done ? "erledigt" : "offen" };
    }
    const hide = typeof input.hide === "boolean" ? input.hide : typeof input.trash === "boolean" ? input.trash : true;
    await this.writeState(claims.sub, "homework", id, "trash", hide);
    if (!hide) await this.writeState(claims.sub, "homework", id, "done", false);
    return { ...item, is_done: hide ? item.is_done : false, is_hidden: hide, status: hide ? "papierkorb" : "offen" };
  }

  timetableDay(query: Record<string, unknown>) {
    this.assertEnabled(); const day = parseDate(query.day, new Date()); const iso = dateOnly(day);
    const isWeekend = day.getUTCDay() === 0 || day.getUTCDay() === 6;
    return { day: iso, day_label: `${englishDays[day.getUTCDay()]} ${day.toLocaleDateString("en-US", { timeZone: "UTC", day: "2-digit", month: "2-digit", year: "numeric" })}`, prev_day: dateOnly(new Date(day.getTime() - 86400000)), next_day: dateOnly(new Date(day.getTime() + 86400000)), today: dateOnly(new Date()), lessons: isWeekend ? [] : [...demoLessons], cache_info: "Sample data" };
  }

  timetableWeek(query: Record<string, unknown>) {
    this.assertEnabled(); const day = parseDate(query.day, new Date()); const monday = new Date(day); monday.setUTCDate(monday.getUTCDate() - (monday.getUTCDay() + 6) % 7);
    const days = Array.from({ length: 5 }, (_, i) => { const current = new Date(monday); current.setUTCDate(monday.getUTCDate() + i); return { date: dateOnly(current), day_name: englishDays[current.getUTCDay()], day_date: current.toLocaleDateString("en-US", { timeZone: "UTC", day: "2-digit", month: "2-digit" }), is_today: dateOnly(current) === dateOnly(new Date()), lessons: [...demoLessons] }; });
    const friday = new Date(monday); friday.setUTCDate(monday.getUTCDate() + 4);
    return { day: dateOnly(day), monday: dateOnly(monday), week_label: `Week ${monday.toLocaleDateString("en-US", { timeZone: "UTC", day: "2-digit", month: "2-digit" })} – ${friday.toLocaleDateString("en-US", { timeZone: "UTC", day: "2-digit", month: "2-digit", year: "numeric" })}`, days, cache_info: "Sample-data week" };
  }

  substitutions(query: Record<string, unknown>) {
    this.assertEnabled(); const day = parseDate(query.day, new Date()); const monday = new Date(day); monday.setUTCDate(monday.getUTCDate() - (monday.getUTCDay() + 6) % 7); const friday = new Date(monday); friday.setUTCDate(monday.getUTCDate() + 4);
    const days = Array.from({ length: 5 }, (_, i) => { const current = new Date(monday); current.setUTCDate(monday.getUTCDate() + i); return { date: dateOnly(current), day_label: `${englishDays[current.getUTCDay()]} ${current.toLocaleDateString("en-US", { timeZone: "UTC" })}`, changes: i === 1 ? [{ class: "8A", lesson: "4", title: "Room change", action: "changeroom" }] : [] }; });
    return { monday: dateOnly(monday), week_label: `Week ${monday.toLocaleDateString("en-US", { timeZone: "UTC", day: "2-digit", month: "2-digit" })} – ${friday.toLocaleDateString("en-US", { timeZone: "UTC", day: "2-digit", month: "2-digit", year: "numeric" })}`, days };
  }

  agenda(query: Record<string, unknown>) {
    this.assertEnabled(); const now = new Date(); const since = parseDate(query.since, new Date(now.getTime() - 30 * 86400000)); const until = parseDate(query.until, new Date(now.getTime() + 60 * 86400000));
    if (until < since || (until.getTime() - since.getTime()) / 86400000 > 366) throw new BadRequestException({ error: t("validation.yearRange"), code: "VALIDATION" });
    const items = [
      { id: 7101, kind: "event", date: dateOnly(new Date(now.getTime() + 3 * 86400000)), text: "Parent-teacher conferences", title: "Parent-teacher conferences", author: "School", type: "parentsevening", timestamp_iso: now.toISOString() },
      { id: 7102, kind: "exam", date: dateOnly(new Date(now.getTime() + 5 * 86400000)), text: "Quiz: forces", title: "Quiz: forces", subject: "Physics", type: "bexam", due: dateOnly(new Date(now.getTime() + 5 * 86400000)), assigned_iso: now.toISOString() },
      { id: 7103, kind: "attendance", date: dateOnly(new Date(now.getTime() - 2 * 86400000)), text: "Attendance confirmed", title: "Attendance confirmed", type: "student_absent", timestamp_iso: now.toISOString() },
    ].filter((item) => item.date >= dateOnly(since) && item.date <= dateOnly(until)).sort((a, b) => a.date.localeCompare(b.date));
    return { items, total: items.length, since: dateOnly(since), until: dateOnly(until), cache_info: "Sample data" };
  }

  grades(query: Record<string, unknown>) { this.assertEnabled(); return { ...this.page([...demoGrades], query), cache_info: "Sample data" }; }

  weather(query: Record<string, unknown>) {
    this.assertEnabled(); const city = typeof query.city === "string" && query.city.trim() ? query.city.trim().slice(0, 100) : "Berlin";
    return { city, today: { temp: 18, max: 20, min: 12, desc: "Partly cloudy", icon: "02d", pop: 10 }, tomorrow: { max: 19, min: 11, desc: "Sunny", icon: "01d", pop: 0 }, day3: { label: englishDays[(new Date().getDay() + 2) % 7], max: 17, min: 10, desc: "Cloudy", icon: "03d", pop: 20 }, hourly: [], details: { feels_like: 17, humidity: 55, pressure: 1013, wind: 3.2, wind_kmh: 12, wind_dir: "W", visibility_km: 10, sunrise: "06:45", sunset: "19:20" } };
  }

  searchCities(query: unknown) {
    this.assertEnabled(); const q = typeof query === "string" ? norm(query.trim()) : "";
    if (q.length < 2) return { items: [] };
    return { items: ["Berlin", "Hamburg", "München", "Wien", "Zürich"].filter((city) => norm(city).includes(q)).map((name) => ({ name, country: "DE", lat: 52.52, lon: 13.405 })) };
  }

  async settings(claims: AuthClaims) {
    this.assertEnabled(); const rows = await this.prisma.userPreference.findMany({ where: { accountId: claims.sub } }); const values = { ...defaults };
    for (const row of rows) if (row.key in values) values[row.key] = row.value;
    return { schema: settingsSchema, values };
  }

  async saveSettings(claims: AuthClaims, body: unknown) {
    this.assertEnabled(); if (typeof body !== "object" || body === null || Array.isArray(body)) throw new BadRequestException({ error: t("validation.jsonObject"), code: "VALIDATION" });
    const current = await this.settings(claims); const input = { ...current.values, ...(body as Record<string, unknown>) } as Record<string, unknown>; const normalized: Record<string, unknown> = {};
    for (const spec of settingsSchema) {
      const raw = input[spec.key]; let value = raw;
      if (spec.kind === "select") value = spec.options?.find(([optionValue]) => optionValue === raw)?.[0] ?? spec.default;
      else if (spec.kind === "bool") value = typeof raw === "boolean" ? raw : ["1", "true", "on"].includes(String(raw));
      else if (spec.kind === "int") { const n = Number(raw); value = Number.isFinite(n) ? Math.min(spec.max ?? n, Math.max(spec.min ?? n, Math.trunc(n))) : spec.default; }
      else if (spec.kind === "order") { const allowed = ["messages", "homework", "weather"]; const selected = (Array.isArray(raw) ? raw : String(raw ?? "").split(",")).filter((key): key is string => typeof key === "string" && allowed.includes(key)); value = [...new Set([...selected, ...allowed])].join(","); }
      else if (spec.kind === "text") value = String(raw ?? "").trim().replace(/[\r\n]/g, " ").slice(0, spec.maxlength ?? 100);
      normalized[spec.key] = value;
      await this.prisma.userPreference.upsert({ where: { accountId_key: { accountId: claims.sub, key: spec.key } }, create: { accountId: claims.sub, key: spec.key, value: value as Prisma.InputJsonValue }, update: { value: value as Prisma.InputJsonValue } });
    }
    return { status: "ok", values: normalized };
  }

  async clearCache(claims: AuthClaims) {
    this.assertEnabled(); const result = await this.prisma.resourceCache.deleteMany({ where: { accountId: claims.sub } }); return { status: "ok", cleared: result.count };
  }
}
