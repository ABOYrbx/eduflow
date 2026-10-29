/**
 * Tests fuer den Session-Proxy unter `app/api/v1/[...path]`.
 *
 * Ohne diese Tests waere die 401-Aufloesung nur von Hand geprueft. Der
 * Proxy haelt die Tokens der Browser aus dem JavaScript heraus — genau
 * deshalb loest er 401 auf, und genau deshalb darf sich hier nichts
 * unbemerkt aendern.
 *
 * Laeuft in `node` (kein DOM noetig, es sind Route-Handler). `fetch` wird
 * ersetzt, das Verhalten der eigentlichen API also simuliert.
 */

const UPSTREAM = "http://127.0.0.1:3000";

/** Antwort des Mock-Servers. */
type Upstream = { status: number; body?: unknown; contentType?: string };

let calls: Array<{ url: string; method: string; auth: string | null; body: string | null }> = [];

/**
 * Mock des API-Servers. `script` beantwortet die Aufrufe in Reihenfolge;
 * jeder Eintrag ist `[Antwort auf den Originalaufruf, Antwort auf auth/refresh]`.
 */
function mockApi(script: (url: string) => Upstream | undefined) {
  calls = [];
  globalThis.fetch = jest.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    const headers = new Headers(init?.headers ?? {});
    calls.push({
      url,
      method: init?.method ?? "GET",
      auth: headers.get("authorization"),
      body: typeof init?.body === "string" ? init.body : null,
    });
    const answer = script(url);
    if (!answer) throw new TypeError("fetch failed");
    return new Response(answer.body === undefined ? null : JSON.stringify(answer.body), {
      status: answer.status,
      headers: { "content-type": answer.contentType ?? "application/json" },
    });
  }) as unknown as typeof fetch;
}

/** Request wie der Browser ihn schickt, inklusive httpOnly-Cookies. */
function request(path: string[], cookies: Record<string, string> = {}) {
  const { NextRequest } = require("next/server") as typeof import("next/server");
  const url = new URL(`http://localhost:3000/api/v1/${path.map(encodeURIComponent).join("/")}`);
  const req = new NextRequest(url, {
    headers: { cookie: Object.entries(cookies).map(([name, value]) => `${name}=${value}`).join("; ") },
  });
  return route.GET(req, { params: Promise.resolve({ path }) }) as Promise<Response>;
}

/** `Set-Cookie`-Kopfzeilen als `name=value;`-Paare. */
function setCookies(response: Response): string[] {
  return response.headers.getSetCookie().map((line) => line.split(";")[0] ?? "");
}

export {}; // Modul: sonst teilen sich beide Spec-Dateien den Namensraum.

const realFetch = globalThis.fetch;
let route: typeof import("./route");

beforeEach(() => {
  process.env.API_SERVER_URL = UPSTREAM;
  jest.resetModules();
  route = require("./route") as typeof import("./route");
});

afterAll(() => {
  globalThis.fetch = realFetch;
});

describe("Session-Proxy", () => {
  it("macht aus dem httpOnly-Cookie einen Bearer-Header", async () => {
    mockApi(() => ({ status: 200, body: { items: [], total: 0, limit: 50, offset: 0 } }));
    const response = await request(["settings"], { eduflow_access: "abc123" });
    expect(response.status).toBe(200);
    expect(calls[0]?.auth).toBe("Bearer abc123");
  });

  it("sendet ohne Cookie keinen Authorization-Header", async () => {
    mockApi(() => ({ status: 401, body: { error: "x", code: "TOKEN_INVALID" } }));
    await request(["settings"]);
    expect(calls[0]?.auth).toBeNull();
  });

  it("haengt Query-Parameter an", async () => {
    mockApi(() => ({ status: 200, body: { items: [] } }));
    const { GET } = route;
    const { NextRequest } = require("next/server") as typeof import("next/server");
    const req = new NextRequest("http://localhost:3000/api/v1/homework?status=offen&limit=200");
    await GET(req, { params: Promise.resolve({ path: ["homework"] }) });
    expect(calls[0]?.url).toContain("status=offen");
    expect(calls[0]?.url).toContain("limit=200");
  });

  it("laesst einen gueltigen Aufruf unangetastet", async () => {
    mockApi(() => ({ status: 200, body: { schema: [], values: {} } }));
    const response = await request(["settings"], { eduflow_access: "gut" });
    expect(response.status).toBe(200);
    // Kein Refresh, weil gar kein 401 kam.
    expect(calls.filter((call) => call.url.includes("auth/refresh"))).toHaveLength(0);
  });

  it("holt ueber auth/refresh ein neues Token, wenn 401 kommt, und wiederholt den Aufruf", async () => {
    mockApi((url) => {
      if (url.includes("auth/refresh")) return { status: 200, body: { token: "neu", refresh_token: "neu-refresh" } };
      return calls.filter((call) => !call.url.includes("auth/refresh")).length === 1
        ? { status: 401, body: { error: "Token abgelaufen", code: "TOKEN_EXPIRED" } }
        : { status: 200, body: { schema: [], values: {} } };
    });

    const response = await request(["settings"], { eduflow_access: "alt" });
    expect(response.status).toBe(200);
    // Erster Versuch mit dem alten, Replay mit dem neuen Token.
    const attempts = calls.filter((call) => !call.url.includes("auth/refresh"));
    expect(attempts.map((call) => call.auth)).toEqual(["Bearer alt", "Bearer neu"]);
    // Und beide Cookies werden neu gesetzt.
    expect(setCookies(response)).toEqual(expect.arrayContaining(["eduflow_access=neu", "eduflow_refresh=neu-refresh"]));
  });

  it("bevorzugt den Refresh-Cookie, wenn es einen gibt", async () => {
    mockApi((url) => {
      if (url.includes("auth/refresh")) return { status: 200, body: { token: "neu", refresh_token: "neu-refresh" } };
      return calls.filter((call) => !call.url.includes("auth/refresh")).length === 1
        ? { status: 401, body: { error: "x", code: "TOKEN_EXPIRED" } }
        : { status: 200, body: {} };
    });
    await request(["settings"], { eduflow_access: "access-token", eduflow_refresh: "refresh-token" });
    // Gesendet wird der Refresh-Token, nicht das (abgelaufene) Access-Token.
    const refresh = calls.find((call) => call.url.includes("auth/refresh"));
    expect(refresh?.body).toBe('{"refresh_token":"refresh-token"}');
  });

  it("benutzt den Access-Token selbst, wenn kein Refresh-Token da ist", async () => {
    // Der echte EduPage-Provider liefert keinen `refresh_token`.
    mockApi((url) => {
      if (url.includes("auth/refresh")) return { status: 200, body: { token: "neu" } };
      return calls.filter((call) => !call.url.includes("auth/refresh")).length === 1
        ? { status: 401, body: { error: "x", code: "TOKEN_INVALID" } }
        : { status: 200, body: {} };
    });

    const response = await request(["me"], { eduflow_access: "alt" });
    expect(response.status).toBe(200);
    const refresh = calls.find((call) => call.url.includes("auth/refresh"));
    expect(refresh?.body).toContain("alt");
    expect(setCookies(response)).toContain("eduflow_access=neu");
  });

  it("loescht alle drei Sitzungs-Cookies, wenn auch der Replay 401 liefert", async () => {
    mockApi(() => ({ status: 401, body: { error: "Token ungueltig", code: "TOKEN_INVALID" } }));
    const response = await request(["settings"], { eduflow_access: "tot", eduflow_refresh: "auch tot", eduflow_pending: "pending" });
    expect(response.status).toBe(401);
    const cookies = setCookies(response);
    expect(cookies).toHaveLength(3);
    expect(cookies.every((cookie) => cookie.endsWith("="))).toBe(true);
    expect(cookies.map((cookie) => cookie.split("=")[0]).sort()).toEqual([
      "eduflow_access", "eduflow_pending", "eduflow_refresh",
    ]);
  });

  it("gibt den 401-Code der API unveraendert weiter", async () => {
    mockApi(() => ({ status: 401, body: { error: "EduPage verlangt 2FA", code: "EDUPAGE_2FA" } }));
    const response = await request(["settings"], { eduflow_access: "x" });
    expect(await response.json()).toEqual({ error: "EduPage verlangt 2FA", code: "EDUPAGE_2FA" });
  });

  it("antwortet mit 502 UPSTREAM, wenn der API-Server nicht erreichbar ist", async () => {
    mockApi(() => undefined);
    const response = await request(["settings"], { eduflow_access: "x" });
    expect(response.status).toBe(502);
    expect((await response.json() as { code: string }).code).toBe("UPSTREAM");
  });

  it("versucht genau einmal zu refreshen, nicht in einer Schleife", async () => {
    mockApi(() => ({ status: 401, body: { error: "x", code: "TOKEN_EXPIRED" } }));
    await request(["settings"], { eduflow_access: "tot" });
    expect(calls.filter((call) => call.url.includes("auth/refresh"))).toHaveLength(1);
    // Zwei Aufrufe: Original und Refresh. Kein Replay, weil der Refresh
    // scheiterte — ohne Erfolg gibt es kein neues Token zum Wiederholen.
    expect(calls).toHaveLength(2);
  });

  it("wiederholt den Aufruf hoechstens einmal, auch wenn der Replay wieder 401 liefert", async () => {
    mockApi((url) => {
      if (url.includes("auth/refresh")) return { status: 200, body: { token: "auch-nicht-gut" } };
      return { status: 401, body: { error: "x", code: "TOKEN_INVALID" } };
    });
    const response = await request(["settings"], { eduflow_access: "alt" });
    expect(response.status).toBe(401);
    expect(calls.filter((call) => !call.url.includes("auth/refresh"))).toHaveLength(2);
    expect(calls.filter((call) => call.url.includes("auth/refresh"))).toHaveLength(1);
    // Und die Sitzung wird dann als tot markiert.
    expect(setCookies(response)).toHaveLength(3);
  });

  it("laesst Fehler ausser 401 unangetastet", async () => {
    mockApi(() => ({ status: 404, body: { error: "nicht gefunden", code: "NOT_FOUND" } }));
    const response = await request(["messages", "99", "thread"], { eduflow_access: "gut" });
    expect(response.status).toBe(404);
    expect(calls.some((call) => call.url.includes("auth/refresh"))).toBe(false);
  });
});
