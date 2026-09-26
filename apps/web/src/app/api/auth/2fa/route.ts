import { NextRequest, NextResponse } from "next/server";

const cookieOptions = { httpOnly: true, secure: process.env.NODE_ENV === "production", sameSite: "lax" as const, path: "/", maxAge: 60 * 60 * 24 * 30 };

export async function POST(request: NextRequest) {
  const pending = request.cookies.get("eduflow_pending")?.value;
  const input: unknown = await request.json().catch(() => null);
  const code = typeof input === "object" && input !== null && "code" in input ? (input as { code?: unknown }).code : undefined;
  if (!pending || typeof code !== "string" || !code) return NextResponse.json({ error: "Bitte den Bestätigungscode erneut eingeben.", code: "PENDING_INVALID" }, { status: 401 });
  const origin = process.env.API_SERVER_URL ?? "http://127.0.0.1:8000";
  const upstream = await fetch(`${origin}/api/v1/auth/2fa`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ pending_token: pending, code }) }).catch(() => null);
  const payload = await upstream?.json().catch(() => ({})) as Record<string, unknown> | undefined;
  if (!upstream || !payload) return NextResponse.json({ error: "Der Server ist nicht erreichbar.", code: "UPSTREAM" }, { status: 502 });
  const response = NextResponse.json({ status: payload.status, error: payload.error, code: payload.code }, { status: upstream.status });
  response.cookies.delete("eduflow_pending");
  if (payload.status === "ok" && typeof payload.token === "string") {
    response.cookies.set("eduflow_access", payload.token, cookieOptions);
    if (typeof payload.refresh_token === "string") response.cookies.set("eduflow_refresh", payload.refresh_token, cookieOptions);
  }
  return response;
}
