import { localeTag, t } from "./i18n";
import type { Lesson, Message } from "./types";

/**
 * Anzeige-Helfer, die mehrere Ansichten teilen (Zeitplan, Nachrichten,
 * Hausaufgaben, Übersicht). Ohne React, damit sie direkt testbar bleiben.
 */

/** `2026-09-25T14:10:00` → `25. September` im aktiven Format. */
export function formatDate(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? value : date.toLocaleDateString(localeTag(), { day: "2-digit", month: "long" });
}

/**
 * Wetter-Glyphe. Der Icon-Code der API (`01` klar, `02`–`04`/`50` wolkig,
 * `09`–`13` nass) hat Vorrang; sonst wird der deutsche Text geraten, damit
 * die Karten auch ohne Icon-Code etwas zeigen.
 */
export function weatherIcon(desc: unknown, icon?: string): string {
  if (icon) {
    const code = icon.slice(0, 2);
    if (code === "01") return "☀";
    if (code === "02" || code === "03" || code === "04" || code === "50") return "☁";
    if (code === "09" || code === "10" || code === "11" || code === "13") return "☂";
  }
  const text = String(desc ?? "").toLowerCase();
  if (/(regen|rain|drizzle|shower|thunder|storm|schauer|gewitter|niesel|schnee|snow|hagel|hail)/.test(text)) return "☂";
  if (/(bewölkt|bewoelkt|wolk|bedeckt|cloud|overcast|nebel|fog|mist|dunst)/.test(text)) return "☁";
  return "☀";
}

/**
 * Index der Stunde, in der die Uhr gerade steht — sonst die erste
 * kommende. Entfallene Stunden werden übersprungen, damit „Jetzt" nicht
 * auf einer Ausfallstunde stehen bleibt.
 */
export function lessonStartIndex(lessons: Lesson[], now: Date): number {
  const nowMinutes = now.getHours() * 60 + now.getMinutes();
  const partsFor = (lesson: Lesson) => lesson.time.split("–").map((time) => time.trim().split(":").map(Number));
  for (let index = 0; index < lessons.length; index++) {
    const lesson = lessons[index]; if (!lesson || lesson.is_cancelled) continue;
    const [start, end] = partsFor(lesson); if (start?.length !== 2 || end?.length !== 2 || !start.every(Number.isFinite) || !end.every(Number.isFinite)) continue;
    if (nowMinutes >= start[0] * 60 + start[1] && nowMinutes <= end[0] * 60 + end[1]) return index;
  }
  for (let index = 0; index < lessons.length; index++) {
    const lesson = lessons[index]; if (!lesson || lesson.is_cancelled) continue;
    const [start] = partsFor(lesson); if (start?.length === 2 && start.every(Number.isFinite) && nowMinutes < start[0] * 60 + start[1]) return index;
  }
  return Math.max(lessons.length - 1, 0);
}

/**
 * Anhänge einer Nachricht: das neue Feld `attachments` hat Vorrang, sonst
 * der Dateiname im `additional_data` älterer EduPage-Nachrichten.
 */
export function messageAttachments(message: Message): string[] {
  if (message.attachments?.length) return message.attachments.map((item) => item.name);
  const filename = (message.additional_data ?? {}).filename;
  return typeof filename === "string" && filename ? [filename] : [];
}

/** Ausführlicher Aufgabenstatus für Überschrift und Zähler. */
export function homeworkStatusLabel(status: string): string {
  if (status === "offen") return t("homework.statusOpen");
  if (status === "überfällig") return t("homework.statusOverdue");
  if (status === "erledigt") return t("homework.statusDone");
  return status;
}

/** Kurzer Status für die Pille an der Karte (inkl. „heute fällig"). */
export function homeworkStatusPill(status: string): string {
  if (status === "offen") return t("homework.open");
  if (status === "heute fällig") return t("homework.dueToday");
  if (status === "überfällig") return t("homework.overdue");
  if (status === "erledigt") return t("homework.done");
  return status;
}
