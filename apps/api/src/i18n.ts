import en from "./messages/en.json";

type Vars = Record<string, string | number>;

/** Englisch ist Quellsprache und Fallback (Crowdin liefert weitere Kataloge). */
export function t(key: string, vars?: Vars): string {
  let node: unknown = en;
  for (const part of key.split(".")) {
    if (typeof node !== "object" || node === null) { node = undefined; break; }
    node = (node as Record<string, unknown>)[part];
  }
  let out = typeof node === "string" ? node : key;
  if (vars) for (const [name, value] of Object.entries(vars)) out = out.split(`{${name}}`).join(String(value));
  return out;
}
