import { NextRequest, NextResponse } from "next/server";
import "../../../../lib/locales";
import { parseAcceptLanguage, resolveLocale, t } from "../../../../lib/i18n";

const apiOrigin = () => process.env.API_SERVER_URL ?? "http://127.0.0.1:3000";
const cookieOptions = { httpOnly: true, secure: process.env.NODE_ENV === "production", sameSite: "lax" as const, path: "/", maxAge: 60 * 60 * 24 * 30 };

export async function POST(request: NextRequest) {
  const locale = resolveLocale([
    request.cookies.get("eduflow_locale")?.value ?? null,
    ...parseAcceptLanguage(request.headers.get("accept-language")),
  ]);
  const body: unknown = await request.json().catch(() => null);
  const upstream = await fetch(`${apiOrigin()}/api/v1/auth/login`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }).catch(() => null);
  const payload = await upstream?.json().catch(() => ({})) as Record<string, unknown> | undefined;
  if (!upstream || !payload) return NextResponse.json({ error: t("common.upstreamUnreachable", undefined, locale), code: "UPSTREAM" }, { status: 502 });
  const response = NextResponse.json({ status: payload.status, message: payload.message, error: payload.error, code: payload.code }, { status: upstream.status });
  if (payload.status === "2fa_required" && typeof payload.pending_token === "string") {
    response.cookies.set("eduflow_pending", payload.pending_token, { ...cookieOptions, maxAge: 600 });
  }
  if (payload.status === "ok" && typeof payload.token === "string") {
    response.cookies.set("eduflow_access", payload.token, cookieOptions);
    if (typeof payload.refresh_token === "string") response.cookies.set("eduflow_refresh", payload.refresh_token, cookieOptions);
  }
  return response;
}
