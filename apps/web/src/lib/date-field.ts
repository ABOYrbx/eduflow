/** Reine Datumslogik für die eigene Kalenderauswahl (ohne React/DOM),
 *  damit sie ohne Browser-DOM testbar bleibt. */

/** Wochentag am Wochenanfang: 0 = Montag … 6 = Sonntag. */
export function firstWeekday(locale: string): number {
  try {
    // getWeekInfo ist noch nicht in den Typen; 1..7 = Mo..So.
    const info = (new Intl.Locale(locale) as unknown as { getWeekInfo?: () => { firstDay?: number } }).getWeekInfo?.();
    // Intl zählt 1..7 = Mo..So, hier 0..6 = Mo..So.
    if (info?.firstDay) return (info.firstDay + 6) % 7;
  } catch {
    /* Intl.Locale.getWeekInfo fehlt → Montag */
  }
  return 0;
}

function pad(value: number): string {
  return String(value).padStart(2, "0");
}

/** Datum → "YYYY-MM-DD" (ohne Zeitzonen-Verschiebung). */
export function toIsoDate(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/** "YYYY-MM-DD" → Datum im lokalen Mitternacht, sonst null. */
export function parseIsoDate(value: string | null | undefined): Date | null {
  if (typeof value !== "string") return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
  if (!match) return null;
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  const date = new Date(year, month - 1, day);
  return date.getMonth() === month - 1 && date.getDate() === day ? date : null;
}

/** Kurzbezeichnung der sieben Wochentage, beginnend am Wochenanfang. */
export function weekdayNames(locale: string, weekStart: number): string[] {
  // 1970-01-05 war ein Montag — Index 0 ohne Umrechnung.
  const names: string[] = [];
  for (let index = 0; index < 7; index += 1) {
    const day = new Date(Date.UTC(1970, 0, 5 + ((weekStart + index) % 7)));
    names.push(new Intl.DateTimeFormat(locale, { weekday: "short", timeZone: "UTC" }).format(day));
  }
  return names;
}

/**
 * Sechs Wochen (42 Tage) als "YYYY-MM-DD" für das angegebene Monatsraster —
 * immer 6 Zeilen, damit die Höhe beim Blättern nicht springt.
 */
export function monthGrid(year: number, month: number, weekStart: number): string[] {
  const first = new Date(year, month, 1);
  const lead = (first.getDay() + 6 - weekStart) % 7;
  const start = new Date(year, month, 1 - lead);
  const days: string[] = [];
  for (let index = 0; index < 42; index += 1) {
    const day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + index);
    days.push(toIsoDate(day));
  }
  return days;
}

/** Einen Monat weiterschalten; Jahr/ Monat 0-basiert. */
export function shiftMonth(year: number, month: number, delta: number): { year: number; month: number } {
  const total = year * 12 + month + delta;
  return { year: Math.floor(total / 12), month: ((total % 12) + 12) % 12 };
}

/** "2026-09-29" → "29.9.2026" in der Zielsprache, sonst Rohwert. */
export function formatIsoDate(value: string, locale: string): string {
  const date = parseIsoDate(value);
  if (!date) return value;
  try {
    return new Intl.DateTimeFormat(locale, { day: "2-digit", month: "2-digit", year: "numeric" }).format(date);
  } catch {
    return value;
  }
}

/** "2026-09" → "September 2026" in der Zielsprache. */
export function formatMonthLabel(year: number, month: number, locale: string): string {
  try {
    return new Intl.DateTimeFormat(locale, { month: "long", year: "numeric" }).format(new Date(year, month, 1));
  } catch {
    return `${year}-${pad(month + 1)}`;
  }
}

/** Zahl um einen Tag/Woche/Monat verschieben, Ergebnis wieder als ISO. */
export function stepIsoDate(value: string, days: number, months = 0): string {
  const date = parseIsoDate(value);
  if (!date) return value;
  if (months) {
    const next = shiftMonth(date.getFullYear(), date.getMonth(), months);
    const lastDay = new Date(next.year, next.month + 1, 0).getDate();
    return toIsoDate(new Date(next.year, next.month, Math.min(date.getDate(), lastDay)));
  }
  return toIsoDate(new Date(date.getFullYear(), date.getMonth(), date.getDate() + days));
}

/** Erster Montag bzw. Sonntag der Woche, in der das Datum liegt. */
export function weekStartIso(value: string, weekStart: number): string {
  const date = parseIsoDate(value);
  if (!date) return value;
  const offset = (date.getDay() + 6 - weekStart) % 7;
  return stepIsoDate(value, -offset);
}
