/** Reine Logik für die Abschnitts-Anordnung der Übersicht (ohne React),
 *  damit sie ohne DOM testbar bleibt. */

/** Gesamter Zustand des Abschnitts-Layouts der Übersicht. */
export type SectionState = { order: string[]; hidden: string[]; spans: Record<string, number> };

/** Bekannte Abschnitte der Übersicht, in Anzeigereihenfolge. */
export const SECTION_KEYS = ["messages", "homework", "weather"];

/** Spalten, die ein Abschnitt belegt (von 12). */
export const SPAN_FULL = 12;
export const SPAN_HALF = 6;

/** Reihenfolge aus einem Einstellungswert lesen; Unbekanntes fällt weg,
 *  fehlende Abschnitte werden hinten ergänzt. */
export function normalizeOrder(value: unknown): string[] {
  const raw = String(value ?? "").split(",").map((part) => part.trim());
  const order = [...new Set(raw.filter((key) => SECTION_KEYS.includes(key)))];
  for (const key of SECTION_KEYS) if (!order.includes(key)) order.push(key);
  return order;
}

/** Ausgeblendete Abschnitte aus einem Einstellungswert lesen. */
export function normalizeHidden(value: unknown): string[] {
  return [...new Set(String(value ?? "").split(",").map((part) => part.trim()).filter((key) => SECTION_KEYS.includes(key)))];
}

/** "messages:6,homework:12" → { messages: 6, homework: 12 }; unbekannte
 *  Schlüssel, ungültige und nicht 6/12-große Werte fallen weg. */
export function normalizeSpans(value: unknown): Record<string, number> {
  const spans: Record<string, number> = {};
  for (const part of String(value ?? "").split(",")) {
    const [key, raw] = part.split(":").map((piece) => piece.trim());
    if (!key || !SECTION_KEYS.includes(key)) continue;
    const span = Number(raw);
    if (span === SPAN_HALF || span === SPAN_FULL) spans[key] = span;
  }
  return spans;
}

/** Breite eines Abschnitts, standardmäßig die volle Breite. */
export function spanOf(spans: Record<string, number>, key: string): number {
  return spans[key] === SPAN_HALF ? SPAN_HALF : SPAN_FULL;
}

/** Zwischen halber und voller Breite wechseln. */
export function toggleSpan(spans: Record<string, number>, key: string): Record<string, number> {
  return { ...spans, [key]: spanOf(spans, key) === SPAN_HALF ? SPAN_FULL : SPAN_HALF };
}

/** Als Einstellungswert schreiben, in fester Reihenfolge. */
export function serializeSpans(spans: Record<string, number>, order: readonly string[]): string {
  return order
    .filter((key) => spans[key] === SPAN_HALF)
    .map((key) => `${key}:${SPAN_HALF}`)
    .join(",");
}

/** Element von einer Position an eine andere verschieben; Grenzen werden
 *  abgeschnitten, unveränderte Eingabe liefert eine Kopie zurück. */
export function moveItem<T>(list: readonly T[], from: number, to: number): T[] {
  const next = [...list];
  if (from < 0 || from >= next.length) return next;
  const target = Math.max(0, Math.min(next.length - 1, to));
  if (target === from) return next;
  const [moved] = next.splice(from, 1);
  next.splice(target, 0, moved);
  return next;
}

/** Schnittpunkt über die Mittellinie statt über die Kante: beim Ziehen über
 *  breite Karten soll die Karte erst wechseln, wenn der Zeiger wirklich
 *  auf der anderen Hälfte steht. */
export function hitIndexByMidline(
  rects: ReadonlyArray<{ top: number; bottom: number }>,
  y: number,
  fallback: number,
): number {
  let best = fallback;
  for (let index = 0; index < rects.length; index += 1) {
    const rect = rects[index];
    if (y < rect.top) break;
    if (y <= rect.bottom) best = index;
  }
  return best;
}
