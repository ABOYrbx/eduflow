/** Einstellungs-Schema (Port von `app.py`, Paket N-F).
 *
 * Form, Labels und Defaults sind wortgleich mit Python; `options` liegen
 * als `[Wert, Label]`-Paare vor (Flask-Tupel → JSON-Arrays).
 */
export interface SettingSpec {
  key: string;
  kind: "select" | "bool" | "int" | "order" | "text";
  label: string;
  options?: Array<[string, string]>;
  default: unknown;
  min?: number;
  max?: number;
  section?: string;
  placeholder?: string;
  maxlength?: number;
  hint?: string;
}

export const OVERVIEW_SECTION_KEYS = ["messages", "homework", "weather"];

export const SETTINGS_SCHEMA: SettingSpec[] = [
  { key: "landing", kind: "select", label: "Startseite nach Anmeldung",
    options: [["uebersicht", "Übersicht"], ["dashboard", "Nachrichten"], ["hausaufgaben", "Hausaufgaben"], ["noten", "Noten"], ["stundenplan", "Stundenplan"]],
    default: "uebersicht" },
  { key: "hw_status", kind: "select", label: "Hausaufgaben: Standardfilter",
    options: [["alle", "Alle"], ["offen", "Nur offene"], ["überfällig", "Nur überfällige"], ["erledigt", "Nur erledigte"], ["papierkorb", "Papierkorb"]],
    default: "alle" },
  { key: "hw_tests", kind: "bool", label: "Hausaufgaben: Tests und Prüfungen standardmäßig einbeziehen", default: false },
  { key: "ov_unread", kind: "int", label: "Übersicht: max. ungelesene Nachrichten", min: 1, max: 50, default: 10 },
  { key: "ov_homework", kind: "int", label: "Übersicht: max. offene Hausaufgaben", min: 1, max: 50, default: 10 },
  { key: "ov_order", kind: "order", section: "Übersicht", label: "Reihenfolge der Übersicht", default: "messages,homework,weather" },
  { key: "ov_wetter", kind: "bool", section: "Wetter", label: "Wetterkarte auf der Übersicht anzeigen",
    hint: "Gilt für die Weboberfläche und die Android-App.", default: true },
  { key: "wetter_city", kind: "text", section: "Wetter", label: "Wetter: Stadt",
    placeholder: "z. B. Berlin", maxlength: 100, hint: "Auswahl gilt für die Wetterkarte auf Web und Android.", default: "" },
];

export const SETTINGS_DEFAULTS: Record<string, unknown> = Object.fromEntries(SETTINGS_SCHEMA.map((spec) => [spec.key, spec.default]));

/** Einzelwert prüfen/normalisieren (Port von `_coerce_setting`). */
export function coerceSetting(spec: SettingSpec, value: unknown): unknown {
  try {
    if (spec.kind === "select") {
      const valid = (spec.options ?? []).map(([option]) => option);
      return valid.includes(typeof value === "string" ? value : "") ? value : spec.default;
    }
    if (spec.kind === "bool") {
      if (typeof value === "boolean") return value;
      return ["1", "true", "on"].includes(String(value));
    }
    if (spec.kind === "int") {
      let parsed: number;
      if (typeof value === "boolean") parsed = value ? 1 : 0;
      else if (typeof value === "number") parsed = Number.isFinite(value) ? Math.trunc(value) : Number.NaN;
      else if (typeof value === "string" && /^[+-]?\d+$/.test(value.trim())) parsed = Number.parseInt(value.trim(), 10);
      else return spec.default;
      if (!Number.isFinite(parsed)) return spec.default;
      return Math.max(spec.min ?? parsed, Math.min(spec.max ?? parsed, parsed));
    }
    if (spec.kind === "order") {
      const raw = Array.isArray(value) ? value : String(value ?? "").split(",");
      const ordered: string[] = [];
      for (const item of raw) {
        const key = String(item).trim();
        if (OVERVIEW_SECTION_KEYS.includes(key) && !ordered.includes(key)) ordered.push(key);
      }
      for (const key of OVERVIEW_SECTION_KEYS) {
        if (!ordered.includes(key)) ordered.push(key);
      }
      return ordered.join(",");
    }
    if (spec.kind === "text") {
      const base = value ? String(value) : "";
      return base.trim().replace(/[\r\n]/g, " ").slice(0, spec.maxlength ?? 500);
    }
  } catch {
    /* unten: Default */
  }
  return spec.default;
}

/** Formular gegen Schema validieren (Port von `settings_from_form`). */
export function settingsFromForm(form: Record<string, unknown>): Record<string, unknown> {
  const values: Record<string, unknown> = {};
  for (const spec of SETTINGS_SCHEMA) {
    if (spec.kind === "bool") {
      values[spec.key] = [form[spec.key] ?? "0"].some((value) => ["1", "true", "on"].includes(String(value)));
    } else {
      values[spec.key] = coerceSetting(spec, form[spec.key]);
    }
  }
  return values;
}
