"use client";

import { useEffect, useId, useRef, useState } from "react";

export type SelectOption = { value: string; label: string; disabled?: boolean };

/**
 * Eigene Auswahl statt native <select>: gleiche Pillen-Optik wie die
 * übrigen Eingabefelder, Menü im Stil der Profilmenü, vollständige
 * Tastaturbedienung (Pfeile, Pos1/Ende, Buchstabensuche, Escape).
 *
 * Für Formulare rendert ein verstecktes Input mit `name` — dadurch
 * funktioniert das Absenden wie bei einem echten select.
 */
export function Select({
  name,
  value,
  defaultValue,
  options,
  onChange,
  ariaLabel,
  labelledBy,
  className = "",
  placeholder,
  menuAlign = "start",
  testId,
}: {
  name?: string;
  value?: string;
  defaultValue?: string;
  options: SelectOption[];
  onChange?: (value: string) => void;
  ariaLabel?: string;
  labelledBy?: string;
  className?: string;
  placeholder?: string;
  menuAlign?: "start" | "end";
  testId?: string;
}) {
  const controlled = value !== undefined;
  const [inner, setInner] = useState(defaultValue ?? options[0]?.value ?? "");
  const current = controlled ? value : inner;
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const wrapRef = useRef<HTMLDivElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const typeAhead = useRef({ text: "", at: 0 });
  const listId = useId();

  const selected = options.find((option) => option.value === current) ?? null;

  useEffect(() => {
    if (!open) return;
    const index = options.findIndex((option) => option.value === current);
    setActive(index >= 0 ? index : 0);
  }, [open, current, options]);

  useEffect(() => {
    if (!open) return;
    function onDown(event: MouseEvent) {
      if (wrapRef.current && !wrapRef.current.contains(event.target as Node)) setOpen(false);
    }
    function onKeyGlobal(event: KeyboardEvent) {
      if (event.key === "Escape") { event.stopPropagation(); setOpen(false); }
    }
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKeyGlobal);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKeyGlobal);
    };
  }, [open]);

  useEffect(() => {
    if (!open) return;
    menuRef.current?.querySelector<HTMLElement>('[data-active="true"]')?.scrollIntoView({ block: "nearest" });
  }, [active, open]);

  function commit(next: string) {
    if (!controlled) setInner(next);
    onChange?.(next);
  }

  function move(step: number) {
    setActive((index) => {
      let next = index;
      for (let i = 0; i < options.length; i += 1) {
        next = (next + step + options.length) % options.length;
        if (!options[next].disabled) break;
      }
      return next;
    });
  }

  function jump(position: "first" | "last") {
    const list = position === "first" ? options : [...options].reverse();
    const found = list.find((option) => !option.disabled);
    if (found) setActive(options.indexOf(found));
  }

  function search(letter: string) {
    const now = Date.now();
    const state = typeAhead.current;
    state.text = now - state.at > 800 ? letter : state.text + letter;
    state.at = now;
    const needle = state.text.toLowerCase();
    const found = options.findIndex((option) => !option.disabled && option.label.toLowerCase().startsWith(needle));
    if (found >= 0) setActive(found);
  }

  function onKeyDown(event: React.KeyboardEvent<HTMLButtonElement>) {
    const key = event.key;
    if (!open && (key === "Enter" || key === " " || key === "ArrowDown" || key === "ArrowUp")) {
      event.preventDefault();
      setOpen(true);
      return;
    }
    if (!open) return;
    if (key === "ArrowDown") { event.preventDefault(); move(1); }
    else if (key === "ArrowUp") { event.preventDefault(); move(-1); }
    else if (key === "Home") { event.preventDefault(); jump("first"); }
    else if (key === "End") { event.preventDefault(); jump("last"); }
    else if (key === "Escape") { event.preventDefault(); setOpen(false); }
    else if (key === "Tab") { setOpen(false); }
    else if (key === "Enter" || key === " ") {
      event.preventDefault();
      const option = options[active];
      if (option && !option.disabled) { commit(option.value); setOpen(false); }
    } else if (key.length === 1 && !event.metaKey && !event.ctrlKey && !event.altKey) {
      event.preventDefault();
      search(key);
    }
  }

  return (
    <div className={`picker${open ? " picker-open" : ""}${className ? ` ${className}` : ""}`} ref={wrapRef}>
      {name ? <input type="hidden" name={name} value={current} /> : null}
      <button
        type="button"
        className="picker-trigger"
        data-testid={testId}
        role="combobox"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listId}
        aria-label={ariaLabel}
        aria-labelledby={labelledBy}
        onClick={() => setOpen((value2) => !value2)}
        onKeyDown={onKeyDown}
      >
        <span className={selected ? "picker-value" : "picker-value picker-placeholder"}>
          {selected ? selected.label : placeholder ?? ""}
        </span>
      </button>
      {open && (
        <div
          className={`picker-menu${menuAlign === "end" ? " picker-menu-end" : ""}`}
          id={listId}
          role="listbox"
          ref={menuRef}
          aria-activedescendant={`${listId}-${active}`}
          aria-labelledby={labelledBy}
          aria-label={ariaLabel}
        >
          {options.map((option, index) => (
            <div
              key={option.value}
              id={`${listId}-${index}`}
              role="option"
              aria-selected={option.value === current}
              aria-disabled={option.disabled || undefined}
              data-active={index === active || undefined}
              className="picker-option"
              onMouseEnter={() => setActive(index)}
              onMouseDown={(event) => event.preventDefault()}
              onClick={() => {
                if (option.disabled) return;
                commit(option.value);
                setOpen(false);
              }}
            >
              <span>{option.label}</span>
              {option.value === current && <span className="picker-check" aria-hidden="true">✓</span>}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
