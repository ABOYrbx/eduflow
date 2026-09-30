"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { t } from "../lib/i18n";
import { useLocale } from "../lib/locale-context";
import { Icon } from "./icon";
import {
  firstWeekday,
  formatIsoDate,
  formatMonthLabel,
  monthGrid,
  parseIsoDate,
  shiftMonth,
  stepIsoDate,
  toIsoDate,
  weekStartIso,
  weekdayNames,
} from "../lib/date-field";

/**
 * Eigene Datumsauswahl statt `input[type=date]`: der Browser liefert einen
 * eigenen Kalender mit eigener Sprache und Optik. Hier trägt stattdessen
 * ein Raster (Pfeiltasten, Pos1/Ende, Bild auf/ab, Enter, Escape) — wie
 * beim Rollen-Menü, nur als Dialog.
 */
export function DateField({
  id,
  name,
  value,
  onChange,
  ariaLabel,
  labelledBy,
  min,
  max,
  className = "",
  placeholder,
}: {
  id?: string;
  name?: string;
  value: string;
  onChange: (value: string) => void;
  ariaLabel?: string;
  labelledBy?: string;
  min?: string;
  max?: string;
  className?: string;
  placeholder?: string;
}) {
  const locale = useLocale();
  const weekStart = useMemo(() => firstWeekday(locale), [locale]);
  const selected = parseIsoDate(value);
  const [open, setOpen] = useState(false);
  const [view, setView] = useState(() => ({ year: selected?.getFullYear() ?? new Date().getFullYear(), month: selected?.getMonth() ?? new Date().getMonth() }));
  const [focused, setFocused] = useState(value);
  const wrapRef = useRef<HTMLDivElement>(null);
  const gridRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function onDown(event: MouseEvent) {
      if (wrapRef.current && !wrapRef.current.contains(event.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, [open]);

  // Fokus in das Raster legen, sobald der Dialog aufgeht.
  useEffect(() => {
    if (!open) return;
    const button = gridRef.current?.querySelector<HTMLButtonElement>('[data-focus="true"]');
    button?.focus();
  }, [open, focused, view]);

  const days = useMemo(() => monthGrid(view.year, view.month, weekStart), [view, weekStart]);
  const labels = useMemo(() => weekdayNames(locale, weekStart), [locale, weekStart]);
  const today = toIsoDate(new Date());

  function blocked(iso: string): boolean {
    return Boolean((min && iso < min) || (max && iso > max));
  }

  function show(next: string) {
    const date = parseIsoDate(next);
    if (!date) return;
    setView({ year: date.getFullYear(), month: date.getMonth() });
    setFocused(next);
  }

  function move(days_: number, months = 0) {
    show(stepIsoDate(focused || value || today, days_, months));
  }

  function onKeyDown(event: React.KeyboardEvent<HTMLDivElement>) {
    const key = event.key;
    if (key === "Escape") { event.preventDefault(); setOpen(false); return; }
    if (key === "ArrowLeft") { event.preventDefault(); move(-1); }
    else if (key === "ArrowRight") { event.preventDefault(); move(1); }
    else if (key === "ArrowUp") { event.preventDefault(); move(-7); }
    else if (key === "ArrowDown") { event.preventDefault(); move(7); }
    else if (key === "PageUp") { event.preventDefault(); move(0, -1); }
    else if (key === "PageDown") { event.preventDefault(); move(0, 1); }
    else if (key === "Home") { event.preventDefault(); show(weekStartIso(focused || today, weekStart)); }
    else if (key === "End") { event.preventDefault(); show(stepIsoDate(weekStartIso(focused || today, weekStart), 6)); }
    else if (key === "Enter" || key === " ") {
      event.preventDefault();
      if (!blocked(focused)) { onChange(focused); setOpen(false); }
    }
  }

  return (
    <div className={`picker date-field${open ? " picker-open" : ""}${className ? ` ${className}` : ""}`} ref={wrapRef}>
      {id ? <input type="hidden" id={id} name={name} value={value} readOnly /> : name ? <input type="hidden" name={name} value={value} readOnly /> : null}
      <button
        type="button"
        className="picker-trigger"
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-label={ariaLabel}
        aria-labelledby={labelledBy}
        onClick={() => { setFocused(value || today); setOpen((state) => !state); }}
        onKeyDown={(event) => {
          if (event.key === "ArrowDown" || event.key === "Enter" || event.key === " ") { event.preventDefault(); setFocused(value || today); setOpen(true); }
        }}
      >
        <span className={value ? "picker-value" : "picker-value picker-placeholder"}>
          {value ? formatIsoDate(value, locale) : placeholder ?? t("common.pickDate")}
        </span>
      </button>
      {open && (
        <div className="cal" role="dialog" aria-label={ariaLabel ?? placeholder ?? t("common.pickDate")} onKeyDown={onKeyDown}>
          <div className="cal-head">
            <button type="button" className="cal-nav" aria-label={t("common.prevMonth")} onClick={() => setView(shiftMonth(view.year, view.month, -1))}>
              <Icon name="left" />
            </button>
            <span className="cal-title">{formatMonthLabel(view.year, view.month, locale)}</span>
            <button type="button" className="cal-nav" aria-label={t("common.nextMonth")} onClick={() => setView(shiftMonth(view.year, view.month, 1))}>
              <Icon name="right" />
            </button>
          </div>
          <div className="cal-week" role="row">
            {labels.map((label) => <span key={label} role="columnheader" aria-label={label}>{label.slice(0, 2)}</span>)}
          </div>
          <div className="cal-grid" role="grid" ref={gridRef}>
            {days.map((iso) => {
              const day = Number(iso.slice(8, 10));
              const outside = Number(iso.slice(5, 7)) !== view.month + 1 || Number(iso.slice(0, 4)) !== view.year;
              const off = blocked(iso);
              return (
                <button
                  key={iso}
                  type="button"
                  role="gridcell"
                  tabIndex={iso === focused ? 0 : -1}
                  data-focus={iso === focused || undefined}
                  data-today={iso === today || undefined}
                  className={`cal-day${outside ? " is-out" : ""}${iso === value ? " is-picked" : ""}`}
                  aria-selected={iso === value}
                  aria-label={formatIsoDate(iso, locale)}
                  aria-current={iso === today ? "date" : undefined}
                  disabled={off}
                  onClick={() => { onChange(iso); setOpen(false); }}
                >
                  {day}
                </button>
              );
            })}
          </div>
          <div className="cal-foot">
            <button type="button" className="btn btn-light btn-sm" onClick={() => { onChange(today); setOpen(false); }}>{t("common.today")}</button>
            <button type="button" className="btn btn-light btn-sm" disabled={!value} onClick={() => { onChange(""); setOpen(false); }}>{t("common.clear")}</button>
          </div>
        </div>
      )}
    </div>
  );
}
