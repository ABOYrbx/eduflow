"use client";

import { useEffect, useRef, useState } from "react";
import { hitIndex, moveItem } from "../lib/section-layout";
import { Icon } from "./icon";

export type SectionLayout = { order: string[]; hidden: string[] };

/**
 * Editor für die Abschnitte der Übersicht: Reihenfolge per Ziehen oder
 * Pfeiltasten, Sichtbarkeit pro Abschnitt. Bewusst als Liste über der
 * Vorschau — die echten Karten enthalten zu viel Zustand, um sie selbst
 * als Ziehziel zu missbrauchen.
 */
export function SectionEditor({
  layout,
  labels,
  hints,
  onChange,
  busy,
}: {
  layout: SectionLayout;
  labels: Record<string, string>;
  hints: Record<string, string>;
  onChange: (next: SectionLayout) => void;
  busy?: boolean;
}) {
  const { order, hidden } = layout;
  const rows = useRef<Array<HTMLDivElement | null>>([]);
  const overIndex = useRef<number | null>(null);
  const fromIndex = useRef<number | null>(null);
  const [dragging, setDragging] = useState<number | null>(null);
  const [target, setTarget] = useState<number | null>(null);

  // Abschluss auch bei verlassenem Fenster, damit nichts hängen bleibt.
  useEffect(() => {
    function stop() {
      fromIndex.current = null;
      overIndex.current = null;
      setDragging(null);
      setTarget(null);
    }
    window.addEventListener("pointercancel", stop);
    window.addEventListener("blur", stop);
    return () => {
      window.removeEventListener("pointercancel", stop);
      window.removeEventListener("blur", stop);
    };
  }, []);

  function move(from: number, to: number) {
    if (from === to) return;
    onChange({ order: moveItem(order, from, to), hidden });
  }

  function startDrag(event: React.PointerEvent<HTMLButtonElement>, index: number) {
    if (event.pointerType === "mouse" && event.button !== 0) return;
    event.preventDefault();
    fromIndex.current = index;
    overIndex.current = index;
    setDragging(index);
    setTarget(index);
    (event.target as HTMLElement).setPointerCapture?.(event.pointerId);

    function onMove(move2: PointerEvent) {
      const rects = rows.current.map((row) => {
        const rect = row?.getBoundingClientRect();
        return rect ? { top: rect.top, bottom: rect.bottom } : { top: 0, bottom: -1 };
      });
      const next = hitIndex(rects, move2.clientY, overIndex.current ?? index);
      if (next !== overIndex.current) {
        overIndex.current = next;
        setTarget(next);
        // Direkt umsortieren, damit die Vorschau beim Ziehen mitwandert.
        if (fromIndex.current !== null) move(fromIndex.current, next);
      }
    }

    function onUp() {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onUp);
      fromIndex.current = null;
      overIndex.current = null;
      setDragging(null);
      setTarget(null);
    }

    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onUp);
  }

  function toggle(key: string) {
    onChange({
      order,
      hidden: hidden.includes(key) ? hidden.filter((item) => item !== key) : [...hidden, key],
    });
  }

  return (
    <div className={`sec-editor${busy ? " is-busy" : ""}`} aria-busy={busy || undefined}>
      {order.map((key, index) => {
        const off = hidden.includes(key);
        return (
          <div
            className={`sec-row${off ? " is-off" : ""}${dragging === index ? " is-dragging" : ""}${target === index && dragging !== null && dragging !== index ? " is-target" : ""}`}
            key={key}
            ref={(element) => { rows.current[index] = element; }}
          >
            <button
              type="button"
              className="sec-grip"
              aria-label={hints.drag ?? key}
              title={hints.drag ?? key}
              onPointerDown={(event) => startDrag(event, index)}
              onKeyDown={(event) => {
                if (event.key === "ArrowUp" && (event.altKey || event.metaKey)) { event.preventDefault(); move(index, index - 1); }
                if (event.key === "ArrowDown" && (event.altKey || event.metaKey)) { event.preventDefault(); move(index, index + 1); }
              }}
            >
              <Icon name="grip" />
            </button>
            <span className="sec-name">{labels[key] ?? key}</span>
            {off && <span className="sec-flag">{hints.hidden ?? ""}</span>}
            <span className="sec-actions">
              <button
                type="button"
                className="sec-btn"
                disabled={index === 0}
                aria-label={`${hints.up ?? ""} ${labels[key] ?? key}`.trim()}
                title={hints.up ?? undefined}
                onClick={() => move(index, index - 1)}
              >
                <Icon name="up" />
              </button>
              <button
                type="button"
                className="sec-btn"
                disabled={index === order.length - 1}
                aria-label={`${hints.down ?? ""} ${labels[key] ?? key}`.trim()}
                title={hints.down ?? undefined}
                onClick={() => move(index, index + 1)}
              >
                <Icon name="down" />
              </button>
              <button
                type="button"
                className="sec-btn"
                aria-pressed={off}
                aria-label={`${off ? (hints.show ?? "") : (hints.hide ?? "")} ${labels[key] ?? key}`.trim()}
                title={off ? hints.show ?? undefined : hints.hide ?? undefined}
                onClick={() => toggle(key)}
              >
                <Icon name={off ? "eyeOff" : "eye"} />
              </button>
            </span>
          </div>
        );
      })}
    </div>
  );
}
