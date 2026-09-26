import { EdupageDataService } from "./data";
import { EdupageClient } from "./client";
import type { FetchImpl } from "./session";
import { sealPassword } from "./vault";

const VAULT_KEY = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
const account = { id: "acct_9", subdomain: "demo", username: "demo" };
const claims = { sub: account.id, jti: "row_0", tokenUse: "access" as const };

const DBI_HOME = '<html><script>userhome({"subdomain":"demo","id":7,"userid":"42","gsec_hash":"gsh-1","dbi":{"students":{"42":{"classid":7}},"classes":{"7":{"name":"5A"}}}});</script></html>';

const SECTION = (cls: string, rows: string): string =>
  `</div><div class="section print-nobreak"><div class="header"><span class="print-font-resizable">${cls}</span><div class="rows">${rows}</div></div>`;
const ROW = (cls: string, period: string, info: string): string =>
  `<div class="row ${cls}"><div class="period"><span class="print-font-resizable">${period}</span></div><div class="info"><span class="print-font-resizable">${info}</span></div></div>`;
const FOOTER = '<div style="text-align:center;font-size:12px"><a href="https://www.asctimetables.com" target="_blank">www.asctimetables.com</a> - foot';
const VIEWER = `<div><span class="print-font-resizable">X</span>`
  + SECTION("5A", ROW("change", "1.", "Mathe"))
  + SECTION("5B", ROW("remove", "2.", "Physik"))
  + FOOTER;

const TIMELINE = [
  { timelineid: "301", typ: "schoolevent", timestamp: "2026-09-18 10:00:00", text: "Ausflug", user_meno: "*", vlastnik_meno: "Schule", data: "{}", removed: "0" },
  { timelineid: "302", typ: "bexam", timestamp: "2026-09-17 08:00:00", text: "", user_meno: "Max", vlastnik_meno: "Anna", data: '{"oldVals":{"date":"2026-09-25","nazov":"Schularbeit","predmet":"Mathe"}}', removed: "0" },
  { timelineid: "303", typ: "student_absent", timestamp: "2026-09-16 08:00:00", text: "Fehlt", user_meno: "Max", vlastnik_meno: "*", data: "{}", removed: "0" },
  { timelineid: "304", typ: "sprava", timestamp: "2026-09-18 10:00:00", text: "Hallo", user_meno: "*", vlastnik_meno: "Anna", data: "{}", removed: "0" },
];

interface Route { status: number; url: string; text: string; }

function stubFetch(): FetchImpl {
  const routes: Record<string, Route> = {
    "GET https://demo.edupage.org/login/?cmd=MainLogin": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin", text: "<html>start</html>" },
    "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken", text: '{"token":"tok-1"}' },
    "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=login": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=login", text: '{"redirectUrl":"/user","err":{}}' },
    "GET https://demo.edupage.org/user": { status: 200, url: "https://demo.edupage.org/user", text: DBI_HOME },
    "POST https://demo.edupage.org/timeline/?module=todo&filterTab=&akcia=getData&filterTab=messages": { status: 200, url: "https://demo.edupage.org/timeline/", text: JSON.stringify({ timelineItems: TIMELINE, timelineUserProps: {} }) },
    "POST https://demo.edupage.org/substitution/server/viewer.js?__func=getSubstViewerDayDataHtml": { status: 200, url: "https://demo.edupage.org/substitution/server/viewer.js?__func=getSubstViewerDayDataHtml", text: JSON.stringify({ r: VIEWER }) },
  };
  return async (url, init) => {
    const route = routes[`${init.method} ${url}`];
    if (!route) throw new Error(`unerwarteter Request: ${init.method} ${url}`);
    return { status: route.status, url: route.url, headers: { get: () => null }, text: async () => route.text, arrayBuffer: async () => new ArrayBuffer(0) };
  };
}

describe("EdupageDataService (Paket N-H, Python-Parität)", () => {
  const oldProvider = process.env.EDUFLOW_PROVIDER;
  const oldKey = process.env.CREDENTIAL_ENCRYPTION_KEY;
  let caches: Map<string, { payload: Record<string, unknown>; expiresAt: Date }>;
  let service: EdupageDataService;
  let sealed: { ciphertext: Buffer; nonce: Buffer };

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
    localResourceState: { findUnique: jest.fn(async () => null), findMany: jest.fn(async () => []), upsert: jest.fn(async () => ({})), create: jest.fn(async () => ({})), deleteMany: jest.fn(async () => ({ count: 0 })) },
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
    jest.clearAllMocks();
    sealed = sealPassword("geheim");
    service = new EdupageDataService(prisma as never, () => new EdupageClient(stubFetch()));
  });

  it("liefert Vertretungen gefiltert mit Wochenlabel wie Python", async () => {
    const week = await service.substitutionsWeek(claims, { day: "2026-09-16" }) as unknown as {
      monday: string; week_label: string; days: { date: string; day_label: string; changes: { class: string; lesson: string }[] }[];
    };
    expect(week.monday).toBe("2026-09-14");
    expect(week.week_label).toBe("Woche 14.09. – 18.09.2026");
    expect(week.days).toHaveLength(5);
    expect(week.days[0]?.day_label).toBe("Montag 14.09.2026");
    expect(week.days[0]?.changes).toEqual([{ class: "5A", lesson: "1", title: "Mathe", action: "change" }]);
    await expect(service.substitutionsWeek(claims, { day: "kein Datum" })).rejects.toMatchObject({ response: { error: "Das Datum muss im Format JJJJ-MM-TT angegeben werden." } });
  });

  it("baut die Agenda mit Arten, Fenster und Sortierung wie Python", async () => {
    const agenda = await service.agenda(claims, { since: "2026-09-15", until: "2026-09-30" }) as unknown as {
      items: { kind: string; date: string; id: number }[]; total: number; since: string; until: string; cache_info: string;
    };
    expect(agenda.items.map((item) => [item.kind, item.date, item.id])).toEqual([
      ["attendance", "2026-09-16", 303],
      ["event", "2026-09-18", 301],
      ["exam", "2026-09-25", 302],
    ]);
    expect(agenda.total).toBe(3);
    expect(agenda.cache_info).toBe("frisch geladen");
    await expect(service.agenda(claims, { since: "2026-09-30", until: "2026-09-15" })).rejects.toMatchObject({ response: { error: "Der Zeitraum darf höchstens ein Jahr umfassen." } });
  });
});
