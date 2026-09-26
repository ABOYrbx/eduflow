import { EdupageDataService, parseBoolFlag } from "./data";
import { EdupageClient } from "./client";
import { homeworkRank, markHidden, parseDueDate } from "./serializers";
import type { FetchImpl } from "./session";
import { sealPassword } from "./vault";

const VAULT_KEY = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
const account = { id: "acct_9", subdomain: "demo", username: "demo" };
const claims = { sub: account.id, jti: "row_0", tokenUse: "access" as const };
const HOME = '<html><script>userhome({"subdomain":"demo","id":7});</script></html>';

const isoDay = (offset: number): string => new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10);

const hwItem = (id: string, type: string, date: string, title: string, subject: string) => ({
  timelineid: id, typ: type, timestamp: "2026-09-18 08:00:00", text: "", user_meno: "Max", vlastnik_meno: "Anna",
  data: JSON.stringify({ oldVals: { date, nazov: title, predmet: subject } }), removed: "0",
});

interface Route { status: number; url: string; text: string; }

function stubFetch(routes: Record<string, Route>, calls: string[] = []): FetchImpl {
  return async (url, init) => {
    calls.push(`${init.method} ${url}`);
    const route = routes[`${init.method} ${url}`];
    if (!route) throw new Error(`unerwarteter Request: ${init.method} ${url}`);
    return { status: route.status, url: route.url, headers: { get: () => null }, text: async () => route.text, arrayBuffer: async () => new ArrayBuffer(0) };
  };
}

describe("EdupageDataService (Paket N-C, Python-Parität)", () => {
  const oldProvider = process.env.EDUFLOW_PROVIDER;
  const oldKey = process.env.CREDENTIAL_ENCRYPTION_KEY;
  let caches: Map<string, { payload: Record<string, unknown>; expiresAt: Date }>;
  let states: Map<string, unknown>;
  let service: EdupageDataService;
  let calls: string[];
  let sealed: { ciphertext: Buffer; nonce: Buffer };

  const routes: Record<string, Route> = {
    "GET https://demo.edupage.org/login/?cmd=MainLogin": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin", text: "<html>start</html>" },
    "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken", text: '{"token":"tok-1"}' },
    "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=login": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=login", text: '{"redirectUrl":"/user","err":{}}' },
    "GET https://demo.edupage.org/user": { status: 200, url: "https://demo.edupage.org/user", text: HOME },
    "POST https://demo.edupage.org/timeline/?module=todo&filterTab=&akcia=getData&filterTab=messages": { status: 200, url: "https://demo.edupage.org/timeline/", text: "" },
    "POST https://demo.edupage.org/timeline/?akcia=homeworkFlag": { status: 200, url: "https://demo.edupage.org/timeline/?akcia=homeworkFlag", text: '{"timelineUserProps":{}}' },
  };

  const prisma = {
    userAccount: { findUnique: jest.fn(async () => account) },
    credentialVault: { findUnique: jest.fn(async () => sealed) },
    resourceCache: {
      findUnique: jest.fn(async ({ where }: { where: { accountId_cacheKey: { accountId: string; cacheKey: string } } }) => {
        const hit = caches.get(`${where.accountId_cacheKey.accountId}|${where.accountId_cacheKey.cacheKey}`);
        return hit ? { accountId: where.accountId_cacheKey.accountId, cacheKey: where.accountId_cacheKey.cacheKey, ...hit } : null;
      }),
      findMany: jest.fn(async () => []),
      upsert: jest.fn(async ({ where, update, create }: { where: { accountId_cacheKey: { accountId: string; cacheKey: string } }; update: Record<string, unknown>; create: Record<string, unknown> }) => {
        const row = { payload: (update.payload ?? create.payload) as Record<string, unknown>, expiresAt: (update.expiresAt ?? create.expiresAt) as Date };
        caches.set(`${where.accountId_cacheKey.accountId}|${where.accountId_cacheKey.cacheKey}`, row);
        return row;
      }),
      deleteMany: jest.fn(async () => ({ count: 0 })),
    },
    localResourceState: {
      findUnique: jest.fn(async ({ where }: { where: { accountId_resource_resourceId_stateKey: { stateKey: string; resourceId: string } } }) => {
        const key = where.accountId_resource_resourceId_stateKey;
        return states.has(`${key.stateKey}:${key.resourceId}`) ? { value: states.get(`${key.stateKey}:${key.resourceId}`) } : null;
      }),
      findMany: jest.fn(async ({ where }: { where: { stateKey?: string } }) => [...states.entries()]
        .filter(([key]) => !where.stateKey || key.startsWith(`${where.stateKey}:`))
        .map(([key, value]) => ({ resourceId: key.split(":")[1], value }))),
      upsert: jest.fn(async ({ where, update, create }: { where: { accountId_resource_resourceId_stateKey: { stateKey: string; resourceId: string } }; update: Record<string, unknown>; create: Record<string, unknown> }) => {
        const key = where.accountId_resource_resourceId_stateKey;
        states.set(`${key.stateKey}:${key.resourceId}`, update.value ?? create.value);
        return {};
      }),
      create: jest.fn(async () => ({})),
      deleteMany: jest.fn(async ({ where }: { where: { stateKey?: string; resourceId?: string } }) => {
        const key = `${where.stateKey}:${where.resourceId}`;
        const had = states.delete(key);
        return { count: had ? 1 : 0 };
      }),
    },
  };

  beforeAll(() => {
    delete process.env.EDUFLOW_PROVIDER;
    process.env.CREDENTIAL_ENCRYPTION_KEY = VAULT_KEY;
  });
  afterAll(() => {
    if (oldProvider === undefined) delete process.env.EDUFLOW_PROVIDER;
    else process.env.EDUFLOW_PROVIDER = oldProvider;
    if (oldKey === undefined) delete process.env.CREDENTIAL_ENCRYPTION_KEY;
    else process.env.CREDENTIAL_ENCRYPTION_KEY = oldKey;
  });
  beforeEach(() => {
    caches = new Map();
    states = new Map();
    calls = [];
    jest.clearAllMocks();
    sealed = sealPassword("geheim");
    service = new EdupageDataService(prisma as never, () => new EdupageClient(stubFetch(routes, calls)));
  });

  const seedTimeline = (items: Record<string, unknown>[]) => {
    const route = routes["POST https://demo.edupage.org/timeline/?module=todo&filterTab=&akcia=getData&filterTab=messages"];
    if (!route) throw new Error("Timeline-Route fehlt");
    route.text = JSON.stringify({ timelineItems: items, timelineUserProps: {} });
  };

  const breakFlag = () => {
    const route = routes["POST https://demo.edupage.org/timeline/?akcia=homeworkFlag"];
    if (!route) throw new Error("Flag-Route fehlt");
    route.text = "kaputt";
  };

  it("listet, zählt, filtert und sortiert wie Python", async () => {
    seedTimeline([
      hwItem("201", "homework", isoDay(-1), "Vokabeln", "Deutsch"),
      hwItem("202", "homework", isoDay(1), "Lesen", "Deutsch"),
      hwItem("203", "bexam", isoDay(1), "Test", "Mathe"),
      hwItem("204", "homework", "", "Ohne Datum", "Kunst"),
    ]);
    const listed = await service.homeworkList(claims, {}) as unknown as { items: { id: number; status: string }[]; counts: Record<string, number> };
    expect(listed.items.map((item) => item.id)).toEqual([201, 202, 204]);
    expect(listed.counts).toEqual({ offen: 1, ueberfaellig: 1, erledigt: 0, papierkorb: 0 });
    const tests = await service.homeworkList(claims, { include_tests: "1" }) as unknown as { items: { id: number }[] };
    expect(tests.items.map((item) => item.id)).toContain(203);
    const overdue = await service.homeworkList(claims, { status: "überfällig" }) as unknown as { items: { id: number }[] };
    expect(overdue.items.map((item) => item.id)).toEqual([201]);
    const searched = await service.homeworkList(claims, { q: "vokabeln" }) as unknown as { items: { id: number }[] };
    expect(searched.items.map((item) => item.id)).toEqual([201]);
    await expect(service.homeworkList(claims, { status: "falsch" })).rejects.toMatchObject({ response: { error: "Ungültiger Status (alle, offen, überfällig, erledigt oder papierkorb erwartet)." } });
    await expect(service.homeworkList(claims, { since: "gestern" })).rejects.toMatchObject({ response: { error: "Ungültiges Datum (YYYY-MM-DD erwartet)." } });
    await expect(service.homeworkList(claims, { include_tests: "vielleicht" })).rejects.toMatchObject({ response: { error: "Ungültiger Wahrheitswert (true/false erwartet)." } });
  });

  it("markiert erledigt und legt in den Papierkorb", async () => {
    seedTimeline([hwItem("201", "homework", isoDay(-1), "Vokabeln", "Deutsch"), hwItem("202", "homework", isoDay(1), "Lesen", "Deutsch")]);
    const done = await service.homeworkDone(claims, "202", { done: true }) as unknown as { is_done: boolean; status: string };
    expect(done).toMatchObject({ is_done: true, status: "erledigt" });
    const trashed = await service.homeworkTrash(claims, "202", {}) as unknown as { is_hidden: boolean };
    expect(trashed.is_hidden).toBe(true);
    const listed = await service.homeworkList(claims, {}) as unknown as { counts: Record<string, number> };
    expect(listed.counts).toEqual({ offen: 0, ueberfaellig: 1, erledigt: 0, papierkorb: 1 });
    const back = await service.homeworkTrash(claims, "202", { hide: false }) as unknown as { is_hidden: boolean; is_done: boolean };
    expect(back).toMatchObject({ is_hidden: false, is_done: false });
    await expect(service.homeworkDone(claims, "999", { done: true })).rejects.toMatchObject({ response: { code: "NOT_FOUND" } });
    await expect(service.homeworkDone(claims, "202", null)).rejects.toMatchObject({ response: { error: "Ungültige Anfrage (JSON erwartet)." } });
  });

  it("meldet Serverfehler beim Flaggen wie Python", async () => {
    seedTimeline([hwItem("201", "homework", isoDay(-1), "Vokabeln", "Deutsch")]);
    breakFlag();
    await expect(service.homeworkDone(claims, "201", { done: true })).rejects.toMatchObject({ response: { error: expect.stringContaining("Status konnte nicht geändert werden:") } });
  });

  it("parst Flags und Daten tolerant", () => {
    expect(parseBoolFlag("ja", false)).toBe(true);
    expect(parseBoolFlag(0, true)).toBe(false);
    expect(parseBoolFlag(undefined, true)).toBe(true);
    expect(() => parseBoolFlag(2, false)).toThrow("Ungültiger Wahrheitswert (0 oder 1 erwartet).");
    expect(homeworkRank({ is_hidden: true, status: "offen" })).toBe(3);
    expect(markHidden([{ id: 1 }, { id: 2 }], new Set(["2"]))).toEqual({ visible: [{ id: 1, is_hidden: false }], deleted: [{ id: 2, is_hidden: true }] });
    expect(parseDueDate("16.09.2026")).toEqual(new Date(2026, 8, 16));
    expect(parseDueDate("nichts")).toBeNull();
  });
});
