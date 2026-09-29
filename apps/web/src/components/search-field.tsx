"use client";

import { t } from "../lib/i18n";
import { Icon } from "./icon";

/**
 * Suchfeld ohne den WebKit-Knopf des Browsers (`::-webkit-search-cancel-button`
 * lässt sich nicht gestalten). Das eigene Kreuz erscheint nur bei Text und
 * setzt den Fokus zurück ins Feld.
 */
export function SearchField({
  value,
  onChange,
  ariaLabel,
  placeholder,
  className = "",
  autoFocus,
}: {
  value: string;
  onChange: (value: string) => void;
  ariaLabel: string;
  placeholder?: string;
  className?: string;
  autoFocus?: boolean;
}) {
  return (
    <span className={`search-wrap${className ? ` ${className}` : ""}`}>
      <Icon name="search" size={15} />
      <input
        type="search"
        value={value}
        aria-label={ariaLabel}
        placeholder={placeholder}
        autoFocus={autoFocus}
        onChange={(event) => onChange(event.target.value)}
      />
      {value && (
        <button type="button" className="search-clear" aria-label={t("common.clearSearch")} title={t("common.clear")} onClick={() => onChange("")}>
          <Icon name="close" size={12} />
        </button>
      )}
    </span>
  );
}
