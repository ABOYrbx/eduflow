"use client";

import { moveItem, spanOf, type SectionState } from "../lib/section-layout";
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
        const off = layout.hidden.includes(key);
        const wide = spanOf(layout.spans, key) === 12;
        return (
          <div className={`sec-row${off ? " is-off" : ""}`} key={key}>
            <span className="sec-name">{labels[key] ?? key}</span>
            {off && <span className="sec-flag">{hints.hidden}</span>}
            <SectionControls
              label={labels[key] ?? key}
              off={off}
              wide={wide}
              first={index === 0}
              last={index === layout.order.length - 1}
              hints={hints}
              onMove={(direction) => onChange({ ...layout, order: moveItem(layout.order, index, index + direction) })}
              onToggle={() => onChange({
                ...layout,
                hidden: off ? layout.hidden.filter((item) => item !== key) : [...layout.hidden, key],
              })}
              onWidth={() => onChange({ ...layout, spans: { ...layout.spans, [key]: wide ? 6 : 12 } })}
            />
          </div>
        );
      })}
    </div>
  );
}
