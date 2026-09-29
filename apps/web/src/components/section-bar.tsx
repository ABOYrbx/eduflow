"use client";

import { useEffect, useState } from "react";
import { hitIndexByMidline, moveItem, SPAN_FULL, spanOf, type SectionState } from "../lib/section-layout";
import { SectionControls, type SectionHints } from "./section-controls";

/**
 * Bedienleiste, die im Bearbeitungsmodus auf jeder Karte der Übersicht
 * sitzt. Ziehen läuft über Zeigerereignisse (auch mit Touch); beim Überqueren
 * der Kartenmitte wird live umsortiert, damit die Vorschau mitwandert.
 *
 * `measure` liefert die Rechtecke der Karten in Anzeigereihenfolge — der
 * Elternteil hält sie, weil nur er die Karten rendert. `sectionKey` ist der
 * Schlüssel aus den Einstellungen, `label` nur die übersetzte Beschriftung.
 */
export function SectionBar({
  sectionKey,
  label,
  state,
  index,
  total,
  hints,
  measure,
  onChange,
}: {
  sectionKey: string;
  label: string;
  state: SectionState;
  index: number;
  total: number;
  hints: SectionHints;
  measure: () => ReadonlyArray<{ top: number; bottom: number }>;
  onChange: (next: SectionState) => void;
}) {
  const [dragging, setDragging] = useState(false);
  const over = { current: index };

  const wide = spanOf(state.spans, sectionKey) === SPAN_FULL;
  const off = state.hidden.includes(sectionKey);

  useEffect(() => {
    function stop() {
      over.current = -1;
      setDragging(false);
    }
    window.addEventListener("pointercancel", stop);
    window.addEventListener("blur", stop);
    return () => {
      window.removeEventListener("pointercancel", stop);
      window.removeEventListener("blur", stop);
    };
  }, []);

  function start(event: React.PointerEvent<HTMLButtonElement>) {
    if (event.pointerType === "mouse" && event.button !== 0) return;
    event.preventDefault();
    over.current = index;
    setDragging(true);

    function onMove(pointer: PointerEvent) {
      const next = hitIndexByMidline(measure(), pointer.clientY, over.current < 0 ? index : over.current);
      if (next === over.current) return;
      over.current = next;
      onChange({ ...state, order: moveItem(state.order, index, next) });
    }

    function onUp() {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onUp);
      over.current = -1;
      setDragging(false);
    }

    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onUp);
  }

  return (
    <div className={`sec-bar${dragging ? " is-dragging" : ""}${off ? " is-off" : ""}`}>
      <span className="sec-bar-name">{label}</span>
      {off && <span className="sec-flag">{hints.hidden}</span>}
      <SectionControls
        label={label}
        off={off}
        wide={wide}
        first={index === 0}
        last={index === total - 1}
        hints={hints}
        onDragStart={start}
        onMove={(direction) => onChange({ ...state, order: moveItem(state.order, index, index + direction) })}
        onToggle={() => onChange({
          ...state,
          hidden: off ? state.hidden.filter((key: string) => key !== sectionKey) : [...state.hidden, sectionKey],
        })}
        onWidth={() => onChange({ ...state, spans: { ...state.spans, [sectionKey]: wide ? 6 : SPAN_FULL } })}
      />
    </div>
  );
}
