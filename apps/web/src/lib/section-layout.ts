/** Reine Logik für die Abschnitts-Anordnung der Übersicht (ohne React),
 *  damit sie ohne DOM testbar bleibt. */

/** Bekannte Abschnitte der Übersicht, in Anzeigereihenfolge. */
export const SECTION_KEYS = ["messages", "homework", "weather"];

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

/** Sichtbaren Schnittpunkt eines Zeigers bestimmen: Index der Zeile, in
 *  der der Zeiger steht, sonst der letzte bekannte Index. */
export function hitIndex(rects: ReadonlyArray<{ top: number; bottom: number }>, y: number, fallback: number): number {
  const found = rects.findIndex((rect) => y >= rect.top && y <= rect.bottom);
  return found >= 0 ? found : fallback;
}
