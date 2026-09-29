import { EdupageDataService, formatAge } from "./data";
import { EdupageClient } from "./client";
import { gradeToDict, parseGrades } from "./grades";
import type { FetchImpl } from "./session";
import { sealPassword } from "./vault";

const VAULT_KEY = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
const account = { id: "acct_9", subdomain: "demo", username: "demo" };
const claims = { sub: account.id, jti: "row_0", tokenUse: "access" as const };

const DBI = {
  subjects: { 29: { short: "Mathe" } },
  teachers: { 5: { firstname: "Anna", lastname: "L" } },
};
const GRADE_DATA = {
  vsetkyZnamky: [
    { udalostid: "11", datum: "2026-09-10 10:00:00", data: "2 (Mitarbeit)" },
    { udalostid: "12", datum: "2026-09-12 10:00:00", data: "18" },
    { udalostid: "13", datum: "2026-09-14 10:00:00", data: "gut" },
  ],
  vsetkyUdalosti: { edupage: {
    11: { p_meno: "Test", PredmetID: "29", UcitelID: "5", p_typ_udalosti: "1", p_vaha: "20", priemer: "2.5" },
    12: { p_meno: "Arbeit", PredmetID: "29", UcitelID: "5", p_typ_udalosti: "2", p_vaha: "20" },
    13: { p_meno: "Referat", PredmetID: "29", UcitelID: null, p_typ_udalosti: "1", p_vaha: "10" },
  } },
};
const HOME = `<html><script>userhome(${JSON.stringify({ subdomain: "demo", id: 7, dbi: DBI })});</script></html>`;
const ZNAMKY = `<html><script>.znamkyStudentViewer(${JSON.stringify(GRADE_DATA)});\r\n\t\t});\r\n\t\t</script></html>`;

function stubFetch(calls: string[] = []): FetchImpl {
  const routes: Record<string, { status: number; url: string; text: string }> = {
    "GET https://demo.edupage.org/login/?cmd=MainLogin": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin", text: "<html>start</html>" },
    "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken", text: '{"token":"tok-1"}' },
    "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=login": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=login", text: '{"redirectUrl":"/user","err":{}}' },
    "GET https://demo.edupage.org/user": { status: 200, url: "https://demo.edupage.org/user", text: HOME },
    "GET https://demo.edupage.org/znamky/": { status: 200, url: "https://demo.edupage.org/znamky/", text: ZNAMKY },
  };
  return async (url, init) => {
    calls.push(`${init.method} ${url}`);
    const route = routes[`${init.method} ${url}`];
    if (!route) throw new Error(`unerwarteter Request: ${init.method} ${url}`);
    return { status: route.status, url: route.url, headers: { get: () => null }, text: async () => route.text, arrayBuffer: async () => new ArrayBuffer(0) };
  };
}

describe("EdupageDataService (Paket N-E, Python-Parität)", () => {
  const oldProvider = process.env.EDUFLOW_PROVIDER;
  const oldKey = process.env.CREDENTIAL_ENCRYPTION_KEY;
  let caches: Map<string, { payload: Record<string, unknown>; expiresAt: Date }>;
  let service: EdupageDataService;
  let calls: string[];
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
    calls = [];
    jest.clearAllMocks();
    sealed = sealPassword("geheim");
    service = new EdupageDataService(prisma as never, () => new EdupageClient(stubFetch(calls)));
  });

  it("parst klassische, Punkte- und Verbalnoten wie Python", () => {
    const parsed = parseGrades(GRADE_DATA as unknown as Record<string, unknown>, DBI);
    expect(parsed).toHaveLength(3);
    const dicts = parsed.map(gradeToDict);
    expect(dicts[0]).toMatchObject({ id: 11, title: "Test", subject: "Mathe", teacher: "Anna L", grade_display: "2", grade_num: 2, badge: "g12", class_avg: 2.5, class_avg_display: "2,5", is_classic: true });
    expect(dicts[1]).toMatchObject({ grade_display: "18", grade_num: null, badge: "gx", grade_sub: "von 20 Punkten · 90 %" });
    expect(dicts[2]).toMatchObject({ grade_display: "gut", grade_num: null, weight_display: "×0,5" });
  });

  it("liefert die Liste frisch und aus dem Cache (ohne Login)", async () => {
    const fresh = await service.gradesList(claims, {}) as unknown as { items: { id: number }[]; total: number; cache_info: string };
    expect(fresh.items.map((item) => item.id)).toEqual([11, 12, 13]);
    expect(fresh.cache_info).toBe("frisch geladen");
    const loginCalls = calls.filter((call) => call.includes("MainLogin")).length;
    const cached = await service.gradesList(claims, {}) as unknown as { cache_info: string };
    expect(cached.cache_info).toMatch(/^aus Cache \(.* alt\)$/);
    expect(calls.filter((call) => call.includes("MainLogin"))).toHaveLength(loginCalls);
    const forced = await service.gradesList(claims, { refresh: "1" }) as unknown as { cache_info: string };
    expect(forced.cache_info).toBe("frisch geladen");
    await expect(service.gradesList(claims, { limit: "x" })).rejects.toMatchObject({ response: { error: "Limit and offset must be integers." } });
  });

  it("formatiert Alter wie cache.format_age", () => {
    expect(formatAge(30)).toBe("30 Sek.");
    expect(formatAge(90)).toBe("1 Min.");
    expect(formatAge(3700)).toBe("1 Std. 1 Min.");
    expect(formatAge(90000)).toBe("1 Tage");
  });
});
