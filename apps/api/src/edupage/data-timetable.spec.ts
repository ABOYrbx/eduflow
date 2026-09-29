import { EdupageDataService } from "./data";
import { EdupageClient } from "./client";
import { isAlldayEvent, lessonToDict, mergeLernzeit, parseDayPlan } from "./timetable";
import type { FetchImpl } from "./session";
import { sealPassword } from "./vault";

const VAULT_KEY = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
const account = { id: "acct_9", subdomain: "demo", username: "demo" };
const claims = { sub: account.id, jti: "row_0", tokenUse: "access" as const };

const DBI = {
  subjects: { 29: { short: "Mathe" }, 30: { short: "Lernzeit" }, 31: { short: "Projekt" }, 32: { short: "Physik" } },
  teachers: { 5: { firstname: "Anna", lastname: "L" }, 6: { firstname: "Ben", lastname: "M" } },
  classrooms: { 12: { short: "A101" }, 13: { short: "A102" } },
};
const HOME = `<html><script>userhome(${JSON.stringify({ subdomain: "demo", id: 7, userid: "U7", dbi: DBI })});</script></html>`;

const PLAN = [
  { uniperiod: "1", starttime: "08:00", endtime: "08:45", subjectid: "29", teacherids: ["5"], classroomids: ["12"], durationperiods: 1, type: "lesson", groupnames: [], flags: {} },
  { uniperiod: "2", starttime: "08:50", endtime: "09:35", subjectid: "30", teacherids: ["6"], classroomids: ["13"], durationperiods: 1, type: "lesson", groupnames: [], flags: { dp0: { note_wd: "Lernzeit" } } },
  { uniperiod: "3", starttime: "09:50", endtime: "10:35", subjectid: "30", teacherids: ["6"], classroomids: ["13"], durationperiods: 1, type: "lesson", groupnames: [], flags: { dp0: { note_wd: "Lernzeit" } } },
  { header: [], subjectid: "1" },
  { uniperiod: "", starttime: "", endtime: "", subjectid: "31", teacherids: [], classroomids: [], type: "event", groupnames: [], flags: { event: { name: "Projekttag" } } },
  { uniperiod: "4", starttime: "10:40", endtime: "11:25", subjectid: "32", teacherids: [], classroomids: [], type: "absent", groupnames: [], flags: {} },
];

interface Route { status: number; url: string; text: string; }

function stubFetch(calls: string[] = []): FetchImpl {
  const routes: Record<string, Route> = {
    "GET https://demo.edupage.org/login/?cmd=MainLogin": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin", text: "<html>start</html>" },
    "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken", text: '{"token":"tok-1"}' },
    "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=login": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=login", text: '{"redirectUrl":"/user","err":{}}' },
    "GET https://demo.edupage.org/user": { status: 200, url: "https://demo.edupage.org/user", text: HOME },
    "GET https://demo.edupage.org/dashboard/eb.php?mode=ttday": { status: 200, url: "https://demo.edupage.org/dashboard/eb.php?mode=ttday", text: '<a href="?gpid=42&x">x</a><script>var gsh=abc123";</script>' },
    "POST https://demo.edupage.org/gcall": { status: 200, url: "https://demo.edupage.org/gcall", text: `U7",${JSON.stringify({ dates: { "2026-09-16": { plan: PLAN } } })},[rest` },
  };
  return async (url, init) => {
    calls.push(`${init.method} ${url}`);
    if (init.method === "POST" && url === "https://demo.edupage.org/gcall") {
      const date = /date=(\d{4}-\d{2}-\d{2})/.exec(init.body ?? "")?.[1] ?? "2026-09-16";
      return { status: 200, url, headers: { get: () => null }, text: async () => `U7",${JSON.stringify({ dates: { [date]: { plan: PLAN } } })},[rest`, arrayBuffer: async () => new ArrayBuffer(0) };
    }
    let route = routes[`${init.method} ${url}`];
    if (!route && init.method === "POST" && url === "https://demo.edupage.org/gcall") route = routes["POST https://demo.edupage.org/gcall"];
    if (!route) throw new Error(`unerwarteter Request: ${init.method} ${url}`);
    return { status: route.status, url: route.url, headers: { get: () => null }, text: async () => route.text, arrayBuffer: async () => new ArrayBuffer(0) };
  };
}

describe("EdupageDataService (Paket N-D, Python-Parität)", () => {
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

  it("liefert den Tag wie Python (Labels, Blöcke, Cache)", async () => {
    const day = await service.timetableDay(claims, { day: "2026-09-16" }) as unknown as { day: string; day_label: string; lessons: { title: string; period: string; time: string }[]; cache_info: string; prev_day: string; next_day: string };
    expect(day.day).toBe("2026-09-16");
    expect(day.day_label).toBe("Mittwoch 16.09.2026");
    expect(day.prev_day).toBe("2026-09-15");
    expect(day.next_day).toBe("2026-09-17");
    expect(day.lessons.map((lesson) => `${lesson.period}|${lesson.title}|${lesson.time}`)).toEqual([
      "1|Mathe|08:00–08:45",
      "2–3|Lernzeit|08:50–10:35",
      "–|Projekt|–––",
      "4|Physik|10:40–11:25",
    ]);
    expect(day.cache_info).toBe("frisch geladen");
    const cached = await service.timetableDay(claims, { day: "2026-09-16" }) as unknown as { cache_info: string };
    expect(cached.cache_info).toBe("aus Cache");
    await expect(service.timetableDay(claims, { day: "kein Datum" })).rejects.toMatchObject({ response: { error: "The date must be given in the format YYYY-MM-DD." } });
  });

  it("liefert die Woche mit Matrix und Cache-Zähler", async () => {
    const week = await service.timetableWeek(claims, { day: "2026-09-16" }) as unknown as { monday: string; week_label: string; days: { date: string; lessons: { title: string }[] }[]; cache_info: string };
    expect(week.monday).toBe("2026-09-14");
    expect(week.week_label).toBe("Woche 14.09. – 18.09.2026");
    expect(week.days).toHaveLength(5);
    expect(week.days[0]?.lessons.map((lesson) => lesson.title)).toEqual(["Mathe", "Lernzeit", "Physik"]);
    expect(week.cache_info).toBe("Woche frisch geladen (5 API-Requests)");
    const again = await service.timetableWeek(claims, { day: "2026-09-16" }) as unknown as { cache_info: string };
    expect(again.cache_info).toBe("Woche aus Cache (0 API-Requests)");
  });

  it("baut Lessons wie lesson_to_dict und filtert Ganztägiges", () => {
    const parsed = parseDayPlan(PLAN, DBI);
    expect(parsed).toHaveLength(5);
    const dicts = parsed.map(lessonToDict);
    expect(dicts[0]).toMatchObject({ period: "1", title: "Mathe", teachers: "Anna L", rooms: "A101", is_cancelled: false });
    expect(dicts[4]).toMatchObject({ title: "Physik", is_cancelled: true });
    const merged = mergeLernzeit(dicts);
    expect(merged[1]).toMatchObject({ period: "2–3", rowspan: 2, row_period: "2" });
    const proj = dicts[3];
    const math = dicts[0];
    if (!proj || !math) throw new Error("keine Lessons");
    expect(isAlldayEvent(proj)).toBe(true);
    expect(isAlldayEvent(math)).toBe(false);
  });
});
