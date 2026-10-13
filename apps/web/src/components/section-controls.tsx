"use client";

import { Icon } from "./icon";

export type SectionHints = {
  drag: string;
  up: string;
  down: string;
  hide: string;
  show: string;
  hidden: string;
  wide: string;
  narrow: string;
};

/** Substitute `{name}` in a hint with the section name. Hints arrive from
 *  the catalog with the placeholder still raw — without this, screen readers
 *  announced "Move {name} up: Messages" verbatim. */
function mitName(template: string, name: string): string {
  return template.replace(/\{name\}/g, name);
}

/**
 * Bedienelemente eines Abschnitts: Ziehen, eine Position hoch/runter,
 * Aus-/Einblenden und zwischen halber und voller Breite wechseln.
 * Weder an den Karten der Übersicht noch in den Einstellungen, damit beide
 * Stellen identisch bedienbar sind.
 */
export function SectionControls({
  label,
  off,
  wide,
  first,
  last,
  hints,
  onDragStart,
  onMove,
  onToggle,
  onWidth,
}: {
  label: string;
  off: boolean;
  wide: boolean;
  first: boolean;
  last: boolean;
  hints: SectionHints;
  onDragStart?: (event: React.PointerEvent<HTMLButtonElement>) => void;
  onMove: (direction: -1 | 1) => void;
  onToggle: () => void;
  onWidth: () => void;
}) {
  return (
    <span className="sec-actions">
      {onDragStart && (
        <button
          type="button"
          className="sec-btn sec-grip"
          aria-label={`${hints.drag}: ${label}`}
          title={hints.drag}
          onPointerDown={onDragStart}
        >
          <Icon name="grip" />
        </button>
      )}
      <button
        type="button"
        className="sec-btn"
        disabled={first}
        aria-label={mitName(hints.up, label)}
        title={mitName(hints.up, label)}
        onClick={() => onMove(-1)}
      >
        <Icon name="up" />
      </button>
      <button
        type="button"
        className="sec-btn"
        disabled={last}
        aria-label={mitName(hints.down, label)}
        title={mitName(hints.down, label)}
        onClick={() => onMove(1)}
      >
        <Icon name="down" />
      </button>
      <button
        type="button"
        className="sec-btn"
        aria-pressed={wide}
        aria-label={mitName(wide ? hints.narrow : hints.wide, label)}
        title={mitName(wide ? hints.narrow : hints.wide, label)}
        onClick={onWidth}
      >
        <Icon name={wide ? "narrow" : "wide"} />
      </button>
      <button
        type="button"
        className="sec-btn"
        aria-pressed={off}
        aria-label={mitName(off ? hints.show : hints.hide, label)}
        title={mitName(off ? hints.show : hints.hide, label)}
        onClick={onToggle}
      >
        <Icon name={off ? "eyeOff" : "eye"} />
      </button>
    </span>
  );
}
