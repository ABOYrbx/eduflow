/**
 * Tests fuer den Datenweg der Web-UI (`lib/api.ts`).
 *
 * Kern ist das 401-Verhalten: der Client schickt den Nutzer zur
 * Anmeldung, statt nur einen Fehlertext in die Ansicht zu legen. Vor
 * diesem Test stand das in keiner Datei und war nur per Hand geprueft.
 */

export {}; // Modul: sonst teilen sich beide Spec-Dateien den Namensraum.

const replace = jest.fn();

/** Antwort des Proxys simulieren. */
function mockFetch(status: number, payload: unknown) {
  globalThis.fetch = jest.fn(async () => new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  })) as unknown as typeof fetch;
}

let api: typeof import("./api");

beforeEach(() => {
  replace.mockReset();
  Object.defineProperty(globalThis, "window", {
    value: { location: { replace } },
    writable: true,
    configurable: true,
  });
  jest.resetModules();
  api = require("./api") as typeof import("./api");
});

const realFetch = globalThis.fetch;
afterAll(() => {
  globalThis.fetch = realFetch;
});

describe("api()", () => {
  it("ruft immer relativ ueber die eigene Origin", async () => {
    mockFetch(200, { items: [] });
    await api.api("/homework?limit=200");
    expect(globalThis.fetch).toHaveBeenCalledWith("/api/v1/homework?limit=200", expect.objectContaining({ cache: "no-store" }));
  });

  it("liefert die Daten bei Erfolg unveraendert zurueck", async () => {
    const page = { items: [{ id: 1 }], total: 1, limit: 50, offset: 0 };
    mockFetch(200, page);
    await expect(api.api("/messages")).resolves.toEqual(page);
  });

  it("setzt den Inhaltstyp nur, wenn ein Body mitgeht", async () => {
    mockFetch(200, {});
    await api.api("/settings");
    const [, init] = (globalThis.fetch as jest.Mock).mock.calls[0] as [string, RequestInit];
    expect((init.headers as Record<string, string>)["content-type"]).toBeUndefined();

    await api.api("/settings", { method: "PUT", body: JSON.stringify({ a: 1 }) });
    const [, init2] = (globalThis.fetch as jest.Mock).mock.calls[1] as [string, RequestInit];
    expect((init2.headers as Record<string, string>)["content-type"]).toBe("application/json");
  });

  it("schickt bei 401 zur Anmeldung", async () => {
    mockFetch(401, { error: "Token abgelaufen.", code: "TOKEN_EXPIRED" });
    await expect(api.api("/settings")).rejects.toThrow("Token abgelaufen.");
    expect(replace).toHaveBeenCalledWith(api.LOGIN_PATH);
  });

  it("schickt bei 401 auch dann zur Anmeldung, wenn kein Text kommt", async () => {
    globalThis.fetch = jest.fn(async () => new Response("", { status: 401 })) as unknown as typeof fetch;
    await expect(api.api("/settings")).rejects.toThrow();
    expect(replace).toHaveBeenCalledWith(api.LOGIN_PATH);
  });

  it("leitet bei 401 per replace, nicht per assign, um", async () => {
    // `assign` wuerde den Eintrag in der Historie lassen, `replace` nicht.
    mockFetch(401, { error: "x", code: "TOKEN_INVALID" });
    await expect(api.api("/me")).rejects.toThrow();
    expect(replace).toHaveBeenCalledTimes(1);
  });

  it("leitet bei anderen Fehlern NICHT um", async () => {
    for (const status of [400, 403, 404, 429, 500, 502]) {
      replace.mockClear();
      mockFetch(status, { error: `Fehler ${status}`, code: "UPSTREAM" });
      await expect(api.api("/settings")).rejects.toThrow(`Fehler ${status}`);
      expect(replace).not.toHaveBeenCalled();
    }
  });

  it("meldet auch ohne Fehlertext einen Fehler statt Erfolg", async () => {
    mockFetch(500, {});
    await expect(api.api("/settings")).rejects.toThrow();
    expect(replace).not.toHaveBeenCalled();
  });
});
