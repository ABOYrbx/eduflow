"use client";

import { moveSection, sectionFlags, toggleHidden, toggleSectionWidth, type SectionState } from "../lib/section-layout";
import { SectionControls, type SectionHints } from "./section-controls";

/**
 * Kompakte Liste derselben Abschnitts-Steuerung für die Einstellungen.
 * Reihenfolge, Sichtbarkeit und Breite werden hier genauso bedient wie an den
 * Karten der Übersicht — beide Stellen teilen sich SectionControls.
 */
export function SectionEditor({
  layout,
  labels,
  hints,
  onChange,
  busy,
}: {
  layout: SectionState;
  labels: Record<string, string>;
  hints: SectionHints;
  onChange: (next: SectionState) => void;
  busy?: boolean;
}) {
  return (
    <div className={`sec-editor${busy ? " is-busy" : ""}`} aria-busy={busy || undefined}>
      {layout.order.map((key, index) => {
        const { off, wide, first, last } = sectionFlags(layout, key, index);
        return (
          <div className={`sec-row${off ? " is-off" : ""}`} key={key}>
            <span className="sec-name">{labels[key] ?? key}</span>
            {off && <span className="sec-flag">{hints.hidden}</span>}
            <SectionControls
              label={labels[key] ?? key}
              off={off}
              wide={wide}
              first={first}
              last={last}
              hints={hints}
              onMove={(direction) => onChange(moveSection(layout, index, direction))}
              onToggle={() => onChange(toggleHidden(layout, key))}
              onWidth={() => onChange(toggleSectionWidth(layout, key))}
            />
          </div>
        );
      })}
    </div>
  );
}
