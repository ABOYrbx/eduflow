export const API_PREFIX = "/api/v1" as const;

export const API_ERROR_CODES = [
  "VALIDATION", "TOKEN_INVALID", "TOKEN_EXPIRED", "PENDING_INVALID",
  "INVALID_CODE", "BAD_CREDENTIALS", "EDUPAGE_2FA", "CAPTCHA_REQUIRED",
  "NOT_FOUND", "RATE_LIMITED", "CONFIG_MISSING", "UPSTREAM",
] as const;

export type ApiErrorCode = (typeof API_ERROR_CODES)[number];
export interface ApiError { error: string; code: ApiErrorCode; }
export interface Page<T> { items: T[]; total: number; limit: number; offset: number; }

export function isApiError(value: unknown): value is ApiError {
  if (typeof value !== "object" || value === null) return false;
  const candidate = value as Record<string, unknown>;
  return typeof candidate.error === "string"
    && typeof candidate.code === "string"
    && API_ERROR_CODES.includes(candidate.code as ApiErrorCode);
}
