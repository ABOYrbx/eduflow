import { BadRequestException } from "@nestjs/common";
import { t } from "../i18n";

/** Paginierungs-Parität zu Python (`api/core.py::get_pagination`, Paket N0).
 *
 * Standard: `limit` 50/max 200, `offset` ab 0. Antwortform überall
 * `{items, total, limit, offset}`. Fehlermeldungen sind bewusst
 * wortgleich mit Python (drahtkompatibel für Android/macOS).
 */
export const PAGE_DEFAULT_LIMIT = 50;
export const PAGE_MAX_LIMIT = 200;

export interface PageQuery { limit: number; offset: number; }
export interface PageResult<T> { items: T[]; total: number; limit: number; offset: number; }

const invalid = (message: string): BadRequestException =>
  new BadRequestException({ error: message, code: "VALIDATION" });

const asInteger = (raw: unknown): number | undefined => {
  if (raw === undefined) return undefined;
  const first = Array.isArray(raw) ? raw[0] : raw;
  if (typeof first === "number") {
    if (!Number.isInteger(first)) throw invalid(t("validation.pagination"));
    return first;
  }
  if (typeof first !== "string") throw invalid(t("validation.pagination"));
  const text = first.trim();
  if (!/^[+-]?\d+$/.test(text)) throw invalid(t("validation.pagination"));
  return Number.parseInt(text, 10);
};

/** Limit/Offset validieren. Wirft 400/VALIDATION mit Python-Texten. */
export function parsePage(
  query: Record<string, unknown>,
  fallback = PAGE_DEFAULT_LIMIT,
  maximum = PAGE_MAX_LIMIT,
): PageQuery {
  const limit = asInteger(query.limit) ?? fallback;
  const offset = asInteger(query.offset) ?? 0;
  if (limit < 1 || limit > maximum) throw invalid(t("validation.limitRange", { max: maximum }));
  if (offset < 0) throw invalid(t("validation.negativeOffset"));
  return { limit, offset };
}

/** Listen-Hüllobjekt wie Python (`api/core.py::page`) bauen. */
export function page<T>(items: T[], query: Record<string, unknown>): PageResult<T> {
  const { limit, offset } = parsePage(query);
  return { items: items.slice(offset, offset + limit), total: items.length, limit, offset };
}
