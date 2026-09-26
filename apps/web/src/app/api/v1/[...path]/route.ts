import { NextRequest, NextResponse } from "next/server";

type Context = { params: Promise<{ path: string[] }> };
const cookieOptions = { httpOnly: true, secure: process.env.NODE_ENV === "production", sameSite: "lax" as const, path: "/", maxAge: 60 * 60 * 24 * 30 };

async function forward(request: NextRequest, context: Context) {
  const { path } = await context.params;
  const origin = process.env.API_SERVER_URL ?? "http://127.0.0.1:8000";
  const target = new URL(`${origin}/api/v1/${path.map(encodeURIComponent).join("/")}`);
  request.nextUrl.searchParams.forEach((value, key) => target.searchParams.append(key, value));
  const access = request.cookies.get("eduflow_access")?.value;
  const refresh = request.cookies.get("eduflow_refresh")?.value;
  const headers = new Headers();
  const contentType = request.headers.get("content-type");
  if (contentType) headers.set("content-type", contentType);
  if (access) headers.set("authorization", `Bearer ${access}`);
  const body = request.method === "GET" || request.method === "HEAD" ? undefined : await request.arrayBuffer();
  let upstream = await fetch(target, { method: request.method, headers, body, cache: "no-store" }).catch(() => null);
  const response = upstream ? new NextResponse(upstream.body, { status: upstream.status, headers: { "content-type": upstream.headers.get("content-type") ?? "application/json" } })
    : NextResponse.json({ error: "Der Server ist nicht erreichbar.", code: "UPSTREAM" }, { status: 502 });
  if (upstream?.status === 401 && refresh) {
    const renewed = await fetch(`${origin}/api/v1/auth/refresh`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ refresh_token: refresh }) }).catch(() => null);
    const tokens = await renewed?.json().catch(() => ({})) as Record<string, unknown> | undefined;
    if (renewed?.ok && typeof tokens?.token === "string" && typeof tokens.refresh_token === "string") {
      headers.set("authorization", `Bearer ${tokens.token}`);
      upstream = await fetch(target, { method: request.method, headers, body, cache: "no-store" }).catch(() => null);
      if (upstream) {
        const retried = new NextResponse(upstream.body, { status: upstream.status, headers: { "content-type": upstream.headers.get("content-type") ?? "application/json" } });
        retried.cookies.set("eduflow_access", tokens.token, cookieOptions);
        retried.cookies.set("eduflow_refresh", tokens.refresh_token, cookieOptions);
        return retried;
      }
    }
  }
  return response;
}

export const GET = forward;
export const POST = forward;
export const PUT = forward;
export const DELETE = forward;
