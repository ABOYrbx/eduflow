/**
 * Logik für das automatische Nachrichten-Update (`MessagesView`, `OverviewView`).
 *
 * Bewusst frei von React: so ist die Erkennung "ist das neu?" offline testbar.
 */

/** Ein-/Zustand des Nachrichten-Pollings. */
export interface LiveMessages {
  /** IDs, die der Nutzer bereits gesehen hat. */
  seen: Set<string>;
  /** Wie viele davon seit dem letzten Aufruf neu dazugekommen sind. */
  count: number;
}

export const emptyLiveMessages: LiveMessages = { seen: new Set<string>(), count: 0 };

/**
 * Ermittelt, welche IDs der frisch geladenen Liste unbekannt sind.
 *
 * `count` bleibt bewusst bestehen: mehrere einzelne Neu-Eintreffer sollen sich
 * addieren ("2 neue", dann "3 neue") und nicht bei jedem Poll neu gezählt
 * werden. Bekannte IDs wandern in `seen`, damit derselbe Poll nicht zweimal
 * zählt.
 */
export function detectNewMessages(current: LiveMessages, incomingIds: string[]): LiveMessages {
  if (current.seen.size === 0) {
    // Erster Abruf: alles gilt als gesehen, sonst meldet der erste Poll die
    // komplette Liste als "neu".
    return { seen: new Set(incomingIds), count: 0 };
  }
  const fresh = incomingIds.filter((id) => !current.seen.has(id));
  if (fresh.length === 0) return current;
  return { seen: new Set([...current.seen, ...fresh]), count: current.count + fresh.length };
}

/** Marker nach Klick/Scrollen zurücksetzen. */
export function clearNewMessages(current: LiveMessages): LiveMessages {
  return current.count === 0 ? current : { ...current, count: 0 };
}