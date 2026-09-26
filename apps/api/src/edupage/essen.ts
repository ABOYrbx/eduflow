import { PDFParse } from "pdf-parse";

/** Wochen-Essensplan der Mensa (Port von `essen.py`, Paket N-G). */

export const ESSEN_TTL_S = Number.parseInt(process.env.EDUFLOW_ESSEN_TTL ?? "21600", 10) || 21600;
export const ESSEN_BASE_URL = (process.env.ESSEN_BASE_URL ?? "https://www.sws-schulen.de").replace(/\/+$/, "");

export const DAY_NAMES = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag"];

const DAY_PATTERN = /(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonnabend|Sonntag)\s*:/g;
const PRICE_PATTERN = /(\d{1,3},\d{2})\s*€/g;
const HEADER_PATTERN = /Speisekarte\s+Montag\s+(\d{1,2})\.(\d{1,2})\.?\s*bis\s*Freitag\s+(\d{1,2})\.(\d{1,2})\.(\d{4})/;

export interface Dish { text: string; price: string; }
export interface MenuDay { date: string; dishes: Dish[]; note: string; }
export interface WeekMenu {
  week: string;
  label: string;
  source_url: string;
  days: Record<string, MenuDay>;
  today: string | null;
  cached?: boolean;
  cache_info?: string;
}

export type FetchBytes = (url: string) => Promise<Buffer | null>;
export type ExtractPdfText = (pdf: Buffer) => Promise<string>;

export const defaultExtractPdfText: ExtractPdfText = async (pdf: Buffer) => {
  let parser: { getText: () => Promise<{ text?: unknown }>; destroy: () => Promise<unknown> } | null = null;
  try {
    parser = new PDFParse({ data: pdf }) as unknown as { getText: () => Promise<{ text?: unknown }>; destroy: () => Promise<unknown> };
    const result = await parser.getText();
    return typeof result?.text === "string" ? result.text : "";
  } finally {
    await parser?.destroy().catch(() => undefined);
  }
};

export const defaultFetchBytes: FetchBytes = async (url: string) => {
  try {
    const response = await fetch(url, { headers: { "User-Agent": "EduFlow/1.0" }, signal: AbortSignal.timeout(8000) });
    if (response.status !== 200 || !response.body) return null;
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let size = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value) {
        size += value.length;
        if (size > 8_000_000) {
          try { await reader.cancel(); } catch { /* egal */ }
          return null;
        }
        chunks.push(value);
      }
    }
    const buf = Buffer.concat(chunks.map((chunk) => Buffer.from(chunk)));
    return buf.subarray(0, 4).toString() === "%PDF" ? buf : null;
  } catch {
    return null;
  }
};

/** ISO-Wochenschlüssel `YYYY-Www` (Port von `week_key`, Donnerstag-Regel). */
export function weekKey(ref: Date): string {
  const monday = new Date(ref);
  monday.setDate(ref.getDate() - ((ref.getDay() + 6) % 7));
  const thursday = new Date(monday.getTime() + 3 * 86400000);
  const isoYear = thursday.getFullYear();
  const jan4 = new Date(isoYear, 0, 4);
  const jan4Monday = new Date(jan4);
  jan4Monday.setDate(jan4.getDate() - ((jan4.getDay() + 6) % 7));
  const week = Math.round((monday.getTime() - jan4Monday.getTime()) / (7 * 86400000)) + 1;
  return `${isoYear}-W${String(week).padStart(2, "0")}`;
}

/** PDF-URL-Kandidaten der KW (Port von `candidate_urls`). */
export function candidateUrls(base: string, isoYear: number, isoWeek: number): string[] {
  const monday = new Date(isoYear, 0, 4);
  monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7) + (isoWeek - 1) * 7);
  const months: Array<[number, number]> = [];
  for (const delta of [0, 7, 14]) {
    const probe = new Date(monday.getTime() - delta * 86400000);
    const key: [number, number] = [probe.getFullYear(), probe.getMonth() + 1];
    if (!months.some(([year, month]) => year === key[0] && month === key[1])) months.push(key);
  }
  const urls: string[] = [];
  const weekStrings = [String(isoWeek), String(isoWeek).padStart(2, "0")];
  for (const [year, month] of months) {
    for (const week of weekStrings) {
      const url = `${base}/wp-content/uploads/${year}/${String(month).padStart(2, "0")}/Mensa-und-Ausser-Haus-${week}.-KW.pdf`;
      if (!urls.includes(url)) urls.push(url);
    }
  }
  return urls;
}

const clean = (value: string): string => value.replace(/\s+/g, " ").trim().replace(/V ollkorn/g, "Vollkorn");

/** Tagesabschnitt → ([Gerichte], Hinweis) (Port von `split_dishes`). */
export function splitDishes(section: string): { dishes: Dish[]; note: string } {
  const parts = (section ?? "").split(PRICE_PATTERN);
  PRICE_PATTERN.lastIndex = 0;
  const dishes: Dish[] = [];
  for (let index = 1; index < parts.length; index += 2) {
    const name = clean(parts[index - 1] ?? "");
    if (name) dishes.push({ text: name, price: `${parts[index]} €` });
  }
  const tail = clean(parts[parts.length - 1] ?? "");
  let note = "";
  if (tail) {
    if (!dishes.length) dishes.push({ text: tail, price: "" });
    else if (tail.length >= 30) note = tail;
  }
  return { dishes, note };
}

/** Gesamttext → ({Tag: (Gerichte, Hinweis)}, Label) (Port von `parse_menu_text`). */
export function parseMenuText(text: string): { days: Record<string, { dishes: Dish[]; note: string }>; label: string | null } {
  const source = text ?? "";
  let label: string | null = null;
  const header = HEADER_PATTERN.exec(source);
  if (header) {
    label = `${Number.parseInt(header[1] ?? "0", 10)}.${Number.parseInt(header[2] ?? "0", 10)}. – ${Number.parseInt(header[3] ?? "0", 10)}.${Number.parseInt(header[4] ?? "0", 10)}.${header[5]}`;
  }
  const found = [...source.matchAll(DAY_PATTERN)];
  const days: Record<string, { dishes: Dish[]; note: string }> = {};
  found.forEach((hit, index) => {
    let name = hit[1] ?? "";
    if (name === "Sonnabend") name = "Samstag";
    const start = (hit.index ?? 0) + hit[0].length;
    const end = index + 1 < found.length ? (found[index + 1]?.index ?? source.length) : source.length;
    const { dishes, note } = splitDishes(source.slice(start, end));
    if (!(name in days)) days[name] = { dishes, note };
  });
  return { days, label };
}

/** PDF-Bytes → Anzeige-Dict (Port von `parse_pdf`). */
export async function parseMenuPdf(pdf: Buffer, isoYear: number, isoWeek: number, extract: ExtractPdfText, today = new Date()): Promise<Omit<WeekMenu, "cached" | "cache_info">> {
  const text = await extract(pdf);
  if (text.trim().length < 50) throw new EssenUnavailable("PDF enthält keinen lesbaren Text.");
  const { days: parsed, label: headerLabel } = parseMenuText(text);
  if (!Object.keys(parsed).length) throw new EssenUnavailable("Im PDF wurden keine Wochentage gefunden.");
  const monday = new Date(isoYear, 0, 4);
  monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7) + (isoWeek - 1) * 7);
  const pad = (value: number): string => String(value).padStart(2, "0");
  const iso = (date: Date): string => `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  let label = headerLabel;
  if (label === null) {
    const friday = new Date(monday.getTime() + 4 * 86400000);
    label = `${monday.getDate()}.${monday.getMonth() + 1}. – ${friday.getDate()}.${friday.getMonth() + 1}.${friday.getFullYear()}`;
  }
  const days: Record<string, MenuDay> = {};
  DAY_NAMES.forEach((name, index) => {
    const entry = parsed[name] ?? { dishes: [], note: "" };
    const date = new Date(monday.getTime() + index * 86400000);
    days[name] = { date: iso(date), dishes: entry.dishes, note: entry.note };
  });
  const sameWeek = weekKey(today) === `${isoYear}-W${String(isoWeek).padStart(2, "0")}`;
  const todayName = sameWeek && today.getDay() >= 1 && today.getDay() <= 5 ? DAY_NAMES[(today.getDay() + 6) % 7] ?? null : null;
  return { week: `${isoYear}-W${String(isoWeek).padStart(2, "0")}`, label, source_url: "", days, today: todayName };
}

export class EssenUnavailable extends Error {}
