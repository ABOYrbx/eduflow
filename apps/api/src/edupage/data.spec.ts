import { EdupageDataService } from "./data";
import { EdupageClient } from "./client";
import { BadCredentialsError } from "./errors";
import type { FetchImpl } from "./session";
import { sealPassword } from "./vault";

const VAULT_KEY = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
const account = { id: "acct_9", subdomain: "demo", username: "demo" };
const claims = { sub: account.id, jti: "row_0", tokenUse: "access" as const };

const DBI_HOME = '<html><script>userhome({"subdomain":"demo","id":7,"dbi":{"teachers":{"5":{"firstname":"Anna","lastname":"Lehrerin","classroomid":"3"}},"students":{"9":{"firstname":"Max","lastname":"A","numberinclass":4}}}});</script></html>';

interface Route { status: number; url: string; text: string; setCookie?: string[]; bytes?: string; }

const timelineItems = (extra: Record<string, unknown>[] = []) => [
  { timelineid: "101", typ: "sprava", timestamp: "2026-09-20 10:00:00", text: "Elternabend", user_meno: "*", vlastnik_meno: "Anna Lehrerin", data: "{}", pocet_reakcii: "2", cas_pridania: "2026-09-20 09:00:00", removed: "0" },
  { timelineid: "102", typ: "homework", timestamp: "2026-09-19 08:00:00", text: "Mathe", user_meno: "Max", vlastnik_meno: "Anna", data: "{}", removed: "0" },
  { timelineid: "103", typ: "sprava", timestamp: "2026-09-21 08:00:00", text: "Antwort", user_meno: "*", vlastnik_meno: "Max", data: '{"textReply":"101"}', removed: "0" },
  { timelineid: "104", typ: "sprava", timestamp: "2026-09-22 08:00:00", text: "Plan", user_meno: "*", vlastnik_meno: "Anna", data: '{"subor":"plan.pdf","url":"/cloud/plan.pdf"}', removed: "0" },
  ...extra,
];

const baseRoutes = (items: Record<string, unknown>[] = timelineItems()): Record<string, Route> => ({
  "GET https://demo.edupage.org/login/?cmd=MainLogin": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin", text: "<html>start</html>" },
  "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken", text: '{"token":"tok-1"}' },
  "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=login": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=login", text: '{"redirectUrl":"/user","err":{}}' },
  "GET https://demo.edupage.org/user": { status: 200, url: "https://demo.edupage.org/user", text: DBI_HOME },
  "POST https://demo.edupage.org/timeline/?module=todo&filterTab=&akcia=getData&filterTab=messages": { status: 200, url: "https://demo.edupage.org/timeline/", text: JSON.stringify({ timelineItems: items, timelineUserProps: {} }) },
  "POST https://demo.edupage.org/timeline/?akcia=getRepliesItem": { status: 200, url: "https://demo.edupage.org/timeline/?akcia=getRepliesItem", text: '{"status":"ok","data":{"reakcie":[{"timelineid":"201","typ":"sprava","vlastnik_meno":"Max","cas_pridania":"2026-09-21 08:05:00","data":"{\\"messageContent\\":\\"Danke\\"}"}]}}' },
  "POST https://demo.edupage.org/timeline/?akcia=createReply": { status: 200, url: "https://demo.edupage.org/timeline/?akcia=createReply", text: '{"status":"ok"}' },
  "POST https://demo.edupage.org/timeline/?=&akcia=createItem&eqav=1&maxEqav=7": { status: 200, url: "https://demo.edupage.org/timeline/", text: '{"changes":[{"timelineid":777}]}' },
  "GET https://demo.edupage.org/cloud/plan.pdf": { status: 200, url: "https://demo.edupage.org/cloud/plan.pdf", text: "", bytes: "PDFDATA" },
});

function stubFetch(routes: Record<string, Route>, calls: string[] = []): FetchImpl {
  return async (url, init) => {
    calls.push(`${init.method} ${url}`);
    const route = routes[`${init.method} ${url}`];
    if (!route) throw new Error(`unerwarteter Request: ${init.method} ${url}`);
    return { status: route.status, url: route.url, headers: { get: () => null }, text: async () => route.text, arrayBuffer: async () => {
      const raw = Buffer.from(route.bytes ?? "");
      return raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength);
    } };
  };
}

describe("EdupageDataService (Paket N-B, Python-Parität)", () => {
  const oldProvider = process.env.EDUFLOW_PROVIDER;
  const oldKey = process.env.CREDENTIAL_ENCRYPTION_KEY;
  let caches: Map<string, { payload: Record<string, unknown>; expiresAt: Date }>;
  let states: Map<string, true>;
  let service: EdupageDataService;
  let calls: string[];

  const prisma = {
    userAccount: { findUnique: jest.fn(async () => account) },
    credentialVault: { findUnique: jest.fn(async () => sealed) },
    resourceCache: {
      findUnique: jest.fn(async ({ where }: { where: { accountId_cacheKey: { accountId: string; cacheKey: string } } }) => {
        const hit = caches.get(`${where.accountId_cacheKey.accountId}|${where.accountId_cacheKey.cacheKey}`);
        return hit ? { accountId: where.accountId_cacheKey.accountId, cacheKey: where.accountId_cacheKey.cacheKey, ...hit } : null;
      }),
      findMany: jest.fn(async ({ where }: { where: { cacheKey?: string } }) => [...caches.entries()]
        .filter(([, row]) => !where.cacheKey || true)
        .map(([key, row]) => ({ cacheKey: key.split("|")[1], ...row }))
        .filter((row) => !where.cacheKey || row.cacheKey === where.cacheKey)),
      upsert: jest.fn(async ({ where, update, create }: { where: { accountId_cacheKey: { accountId: string; cacheKey: string } }; update: Record<string, unknown>; create: Record<string, unknown> }) => {
        const key = `${where.accountId_cacheKey.accountId}|${where.accountId_cacheKey.cacheKey}`;
        const row = { payload: (update.payload ?? create.payload) as Record<string, unknown>, expiresAt: (update.expiresAt ?? create.expiresAt) as Date };
        caches.set(key, row);
        return row;
      }),
      deleteMany: jest.fn(async () => ({ count: 0 })),
    },
    localResourceState: {
      findUnique: jest.fn(async ({ where }: { where: { accountId_resource_resourceId_stateKey: { resourceId: string } } }) =>
        states.has(where.accountId_resource_resourceId_stateKey.resourceId) ? { value: true } : null),
      create: jest.fn(async ({ data }: { data: { resourceId: string } }) => { states.set(data.resourceId, true); return {}; }),
    },
  };
  let sealed: { ciphertext: Buffer; nonce: Buffer };

  const factoryFor = (routes: Record<string, Route>) => () => new EdupageClient(stubFetch(routes, calls));

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
    service = new EdupageDataService(prisma as never, factoryFor(baseRoutes()));
  });

  it("listet, sucht, filtert und blättert wie Python", async () => {
    const listed = await service.messages(claims, {}) as unknown as { items: { id: number }[]; total: number };
    expect(listed.items.map((item) => item.id)).toEqual([104, 101]);
    expect(listed.total).toBe(2);
    const searched = await service.messages(claims, { q: "Elternabend" }) as unknown as { items: { id: number }[] };
    expect(searched.items.map((item) => item.id)).toEqual([101]);
    const paged = await service.messages(claims, { limit: "1", offset: "1" }) as unknown as { items: { id: number }[]; limit: number; offset: number };
    expect(paged.items.map((item) => item.id)).toEqual([101]);
    expect(paged).toMatchObject({ limit: 1, offset: 1, total: 2 });
    await expect(service.messages(claims, { type: "homework" })).rejects.toMatchObject({ response: { code: "VALIDATION", error: "Unbekannter Nachrichtentyp. Gültig: anketa, chat, genotif, news, sprava." } });
    await expect(service.messages(claims, { since: "gestern" })).rejects.toMatchObject({ response: { code: "VALIDATION" } });
    await expect(service.messages(claims, { limit: "0" })).rejects.toMatchObject({ response: { error: "Limit muss zwischen 1 und 200 liegen." } });
  });

  it("liefert Threads frisch und aus dem Cache", async () => {
    const fresh = await service.thread(claims, 101, false) as unknown as { cached: boolean; summary: unknown };
    expect(fresh.cached).toBe(false);
    expect(fresh.summary).toMatchObject({ replies: 1 });
    const fetchCount = calls.filter((call) => call.includes("getRepliesItem")).length;
    const cached = await service.thread(claims, 101, false) as unknown as { cached: boolean };
    expect(cached.cached).toBe(true);
    expect(calls.filter((call) => call.includes("getRepliesItem"))).toHaveLength(fetchCount);
    await expect(service.thread(claims, Number.NaN, false)).rejects.toMatchObject({ response: { code: "NOT_FOUND" } });
  });

  it("markiert Gelesenes nur aus dem Cache", async () => {
    await expect(service.markRead(claims)).resolves.toEqual({ marked: 0 });
    await service.messages(claims, {});
    await expect(service.markRead(claims)).resolves.toEqual({ marked: 3 });
    await expect(service.markRead(claims)).resolves.toEqual({ marked: 0 });
  });

  it("listet Empfänger aus dbi mit Paginierung", async () => {
    const recs = await service.recipients(claims, {}) as unknown as { items: { id: string }[]; total: number };
    expect(recs.items.map((item) => item.id)).toEqual(["Teacher5", "Student9"]);
    expect(recs.total).toBe(2);
  });

  it("validiert Senden und liefert die neue Nachricht", async () => {
    await expect(service.send(claims, {})).rejects.toMatchObject({ response: { error: "Bitte mindestens einen gültigen Empfänger angeben." } });
    await expect(service.send(claims, { recipients: ["Teacher5"], body: "  " })).rejects.toMatchObject({ response: { error: "Bitte einen Nachrichtentext eingeben." } });
    const extra = [{ timelineid: "777", typ: "sprava", timestamp: "2026-09-23 09:00:00", text: "Neu", user_meno: "*", vlastnik_meno: "Ich", data: "{}", removed: "0" }];
    service = new EdupageDataService(prisma as never, factoryFor(baseRoutes([...timelineItems(), ...extra])));
    const sent = await service.send(claims, { recipients: ["Teacher5", "Teacher5", "x"], body: "Hallo" }) as unknown as { id: number; text: string };
    expect(sent).toMatchObject({ id: 777, text: "Neu" });
  });

  it("sendet an Schüler mit nicht-numerischem dbi-Schlüssel", async () => {
    const home = '<html><script>userhome({"subdomain":"demo","id":7,"dbi":{"teachers":{"5":{"firstname":"Anna","lastname":"Lehrerin","classroomid":"3"}},"students":{"s-12":{"firstname":"Lena","lastname":"B","numberinclass":4}}}});</script></html>';
    const extra = [{ timelineid: "777", typ: "sprava", timestamp: "2026-09-23 09:00:00", text: "Neu", user_meno: "*", vlastnik_meno: "Ich", data: "{}", removed: "0" }];
    const routes = baseRoutes([...timelineItems(), ...extra]);
    routes["GET https://demo.edupage.org/user"] = { status: 200, url: "https://demo.edupage.org/user", text: home };
    const svc = new EdupageDataService(prisma as never, factoryFor(routes));
    const recs = await svc.recipients(claims, {}) as unknown as { items: { id: string }[] };
    expect(recs.items.map((item) => item.id)).toEqual(["Teacher5", "Students-12"]);
    const sent = await svc.send(claims, { recipients: ["Students-12"], body: "Hallo" }) as unknown as { id: number };
    expect(sent).toMatchObject({ id: 777 });
    await expect(svc.send(claims, { recipients: ["Unbekannt1"], body: "Hallo" }))
      .rejects.toMatchObject({ response: { error: "Bitte mindestens einen gültigen Empfänger angeben." } });
  });

  it("antwortet und frischt den Thread auf", async () => {
    await expect(service.reply(claims, 101, {})).rejects.toMatchObject({ response: { error: "Bitte einen Antworttext eingeben." } });
    const answered = await service.reply(claims, 101, { body: "Gerne" }) as unknown as { cached: boolean; summary: unknown };
    expect(answered.cached).toBe(false);
    expect(answered.summary).toMatchObject({ replies: 1 });
  });

  it("vergibt Download-Tokens und lädt per dl", async () => {
    await expect(service.downloadToken(claims, { event_id: 101, idx: -1 })).rejects.toMatchObject({ response: { code: "VALIDATION" } });
    await expect(service.downloadToken(claims, { event_id: 999, idx: 0 })).rejects.toMatchObject({ response: { code: "NOT_FOUND" } });
    const issued = await service.downloadToken(claims, { event_id: 104, idx: 0 }) as unknown as { download_token: string; expires_in: number };
    expect(issued.expires_in).toBe(300);
    const file = await service.attachmentByDl(issued.download_token, 104, 0);
    expect(file.filename).toBe("plan.pdf");
    expect(Buffer.from(file.bytes).toString()).toBe("PDFDATA");
    await expect(service.attachmentByDl(issued.download_token, 104, 1)).rejects.toMatchObject({ response: { code: "TOKEN_INVALID" } });
    const direct = await service.attachmentByClaims(claims, 104, 0);
    expect(direct.contentType).toBe("application/octet-stream");
  });

  it("mappt Anmeldefehler mit N-B-Texten", async () => {
    const failing = new EdupageDataService(prisma as never, () => ({ login: async () => { throw new BadCredentialsError(); } }) as never);
    await expect(failing.messages(claims, {})).rejects.toMatchObject({ response: { code: "BAD_CREDENTIALS", error: "Benutzername, Passwort oder Subdomain ist falsch." } });
    const needs2fa = new EdupageDataService(prisma as never, () => ({ login: async () => ({ outcome: "twofactor" }) }) as never);
    await expect(needs2fa.messages(claims, {})).rejects.toMatchObject({ response: { code: "EDUPAGE_2FA" } });
  });
});
