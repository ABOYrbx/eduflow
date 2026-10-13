"use client";

import { useEffect, useRef, useState } from "react";
import { hitIndexByMidline, moveItem, spanOf, type SectionState } from "../lib/section-layout";
import { SectionControls, type SectionHints } from "./section-controls";

/**
 * Arranges the overview sections in the settings: order, visibility and
 * width. Dragging runs through pointer events (touch included); the arrows
 * remain as a keyboard-operable alternative.
 *
 * Deliberately the only place for arranging sections — the edit mode on the
 * overview itself is gone. The editor is part of the settings form and is
 * only applied on "Save".
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
  const [dragging, setDragging] = useState<string | null>(null);
  const rows = useRef<Record<string, HTMLDivElement | null>>({});
  // Applied repeatedly while dragging: the pointer listeners live outside
  // React and would otherwise close over a stale state.
  const live = useRef(layout);
  live.current = layout;

  useEffect(() => {
    function stop() { setDragging(null); }
    window.addEventListener("pointercancel", stop);
    window.addEventListener("blur", stop);
    return () => {
      window.removeEventListener("pointercancel", stop);
      window.removeEventListener("blur", stop);
    };
  }, []);

  function measure(): ReadonlyArray<{ top: number; bottom: number }> {
    return live.current.order
      .map((key) => rows.current[key]?.getBoundingClientRect())
      .filter((rect): rect is DOMRect => Boolean(rect))
      .map((rect) => ({ top: rect.top, bottom: rect.bottom }));
  }

  function startDrag(event: React.PointerEvent<HTMLButtonElement>, key: string, index: number) {
    if (event.pointerType === "mouse" && event.button !== 0) return;
    event.preventDefault();
    setDragging(key);
    let from = index;
    let over = index;

    function onMove(pointer: PointerEvent) {
      const next = hitIndexByMidline(measure(), pointer.clientY, over);
      if (next === over) return;
      over = next;
      onChange({ ...live.current, order: moveItem(live.current.order, from, next) });
      from = next;
    }

    function onUp() {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onUp);
      setDragging(null);
    }

    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onUp);
  }

  return (
    <div className={`sec-editor${busy ? " is-busy" : ""}`} aria-busy={busy || undefined}>
      {layout.order.map((key, index) => {
        const off = layout.hidden.includes(key);
        const wide = spanOf(layout.spans, key) === 12;
        return (
          <div
            className={`sec-row${off ? " is-off" : ""}${dragging === key ? " is-dragging" : ""}`}
            key={key}
            ref={(element) => { rows.current[key] = element; }}
          >
            <span className="sec-name">{labels[key] ?? key}</span>
            {off && <span className="sec-flag">{hints.hidden}</span>}
            <SectionControls
              label={labels[key] ?? key}
              off={off}
              wide={wide}
              first={index === 0}
              last={index === layout.order.length - 1}
              hints={hints}
              onDragStart={(event) => startDrag(event, key, index)}
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