import { NextRequest, NextResponse } from "next/server";
import "../../../../lib/locales";
import { parseAcceptLanguage, resolveLocale, t } from "../../../../lib/i18n";

type Context = { params: Promise<{ path: string[] }> };
const cookieOptions = { httpOnly: true, secure: process.env.NODE_ENV === "production", sameSite: "lax" as const, path: "/", maxAge: 60 * 60 * 24 * 30 };

/**
 * Session-Proxy: der Browser ruft nur `/api/v1/*` der eigenen Origin.
 * Hier wird aus dem httpOnly-Cookie ein Bearer-Header und an
 * `$API_SERVER_URL` weitergereicht — Tokens sind damit nie im JS.
 *
 * `401` wird genau einmal aufgelöst:
 *  1. `auth/refresh` mit `eduflow_refresh`, sonst — der echte EduPage-
 *     Provider liefert keinen Refresh-Token, nimmt aber das Access-Token
 *     selbst (`AuthController.refresh`) — mit dem Access-Token.
 *  2. Replay mit dem neuen Token. Bleibt es bei 401, ist die Sitzung tot:
 *     Cookies werden geleert, damit der Client sauber zur Anmeldung geht.
 */
async function renew(origin: string, token: string): Promise<{ token: string; refresh_token: string | null } | null> {
  const renewed = await fetch(`${origin}/api/v1/auth/refresh`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ refresh_token: token }),
  }).catch(() => null);
  const tokens = await renewed?.json().catch(() => ({})) as Record<string, unknown> | undefined;
  if (!renewed?.ok || typeof tokens?.token !== "string") return null;
  return { token: tokens.token, refresh_token: typeof tokens.refresh_token === "string" ? tokens.refresh_token : null };
}

async function forward(request: NextRequest, context: Context) {
  const locale = resolveLocale([
    request.cookies.get("eduflow_locale")?.value ?? null,
    ...parseAcceptLanguage(request.headers.get("accept-language")),
  ]);
  const { path } = await context.params;
  const origin = process.env.API_SERVER_URL ?? "http://127.0.0.1:3000";
  const target = new URL(`${origin}/api/v1/${path.map(encodeURIComponent).join("/")}`);
  request.nextUrl.searchParams.forEach((value, key) => target.searchParams.append(key, value));
  const access = request.cookies.get("eduflow_access")?.value;
  const refresh = request.cookies.get("eduflow_refresh")?.value;
  const headers = new Headers();
  const contentType = request.headers.get("content-type");
  if (contentType) headers.set("content-type", contentType);
  if (access) headers.set("authorization", `Bearer ${access}`);
  const body = request.method === "GET" || request.method === "HEAD" ? undefined : await request.arrayBuffer();

  const upstreamCall = () => fetch(target, { method: request.method, headers, body, cache: "no-store" }).catch(() => null);
  const build = (upstream: Response) => new NextResponse(upstream.body, {
    status: upstream.status,
    headers: { "content-type": upstream.headers.get("content-type") ?? "application/json" },
  });

  let upstream = await upstreamCall();
  if (upstream?.status === 401 && (refresh ?? access)) {
    const renewed = await renew(origin, refresh ?? access as string);
    if (renewed) {
      headers.set("authorization", `Bearer ${renewed.token}`);
      upstream = await upstreamCall();
      if (upstream && upstream.status !== 401) {
        const retried = build(upstream);
        retried.cookies.set("eduflow_access", renewed.token, cookieOptions);
        if (renewed.refresh_token) retried.cookies.set("eduflow_refresh", renewed.refresh_token, cookieOptions);
        return retried;
      }
    }
  }

  if (!upstream) {
    return NextResponse.json({ error: t("common.upstreamUnreachable", undefined, locale), code: "UPSTREAM" }, { status: 502 });
  }
  const response = build(upstream);
  if (upstream.status === 401) {
    // Sitzung endgültig ungültig: httpOnly-Cookies weg, der Client
    // schickt den Nutzer daraufhin zu `LOGIN_PATH`.
    response.cookies.delete("eduflow_access");
    response.cookies.delete("eduflow_refresh");
    response.cookies.delete("eduflow_pending");
  }
  return response;
}

export const GET = forward;
export const POST = forward;
export const PUT = forward;
export const DELETE = forward;
