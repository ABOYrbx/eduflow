"use client";

import { useRef } from "react";
import { Icon } from "./icon";

/**
 * Zahlenfeld ohne Browser-Stepper: die Pfeile des Browsers lassen sich nicht
 * gestalten, also blendet `appearance:textfield` sie aus und hier kommen
 * eigene Knöpfe. Das echte input bleibt für Formular, Tastatur und
 * Screenreader erhalten; `stepUp`/`stepDown` halten die min/max-Grenzen ein.
 */
export function NumberField({
  id,
  name,
  value,
  min,
  max,
  step = 1,
  onChange,
  ariaLabel,
  labelledBy,
  className = "",
}: {
  id?: string;
  name?: string;
  value: number;
  min?: number;
  max?: number;
  step?: number;
  onChange: (value: number) => void;
  ariaLabel?: string;
  labelledBy?: string;
  className?: string;
}) {
  const ref = useRef<HTMLInputElement>(null);

  function bump(direction: 1 | -1) {
    const input = ref.current;
    if (!input) return;
    if (direction === 1) input.stepUp();
    else input.stepDown();
    onChange(input.valueAsNumber || 0);
  }

  return (
    <div className={`num-field${className ? ` ${className}` : ""}`}>
      <input
        className="input-pill"
        ref={ref}
        id={id}
        name={name}
        type="number"
        inputMode="numeric"
        min={min}
        max={max}
        step={step}
        value={Number.isFinite(value) ? value : (min ?? 0)}
        aria-label={ariaLabel}
        aria-labelledby={labelledBy}
        onChange={(event) => onChange(event.target.valueAsNumber || 0)}
      />
      <span className="num-step" aria-hidden="true">
        <button type="button" className="num-btn" tabIndex={-1} disabled={min !== undefined && value <= min} onClick={() => bump(1)}>
          <Icon name="up" size={12} />
        </button>
        <button type="button" className="num-btn" tabIndex={-1} disabled={max !== undefined && value >= max} onClick={() => bump(-1)}>
          <Icon name="down" size={12} />
        </button>
      </span>
    </div>
  );
}
