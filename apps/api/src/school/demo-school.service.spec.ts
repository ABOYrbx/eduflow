import { DemoSchoolService } from "./demo-school.service";

describe("DemoSchoolService", () => {
  const states = new Map<string, unknown>();
  let service: DemoSchoolService;
  let originalProvider: string | undefined;
  const keyOf = (data: Record<string, string>) => [data.accountId, data.resource, data.resourceId, data.stateKey].join(":");
  const prisma = {
    localResourceState: {
      findMany: jest.fn(async ({ where }: { where: Record<string, string> }) => [...states.entries()].flatMap(([key, value]) => {
        const [accountId, resource, resourceId, stateKey] = key.split(":");
        return accountId === where.accountId && resource === where.resource && stateKey === where.stateKey ? [{ accountId, resource, resourceId, stateKey, value }] : [];
      })),
      findUnique: jest.fn(async ({ where }: { where: { accountId_resource_resourceId_stateKey: Record<string, string> } }) => {
        const data = where.accountId_resource_resourceId_stateKey; const value = states.get(keyOf(data));
        return value === undefined ? null : { value };
      }),
      upsert: jest.fn(async ({ where, create, update }: { where: { accountId_resource_resourceId_stateKey: Record<string, string> }; create: Record<string, unknown>; update: Record<string, unknown> }) => {
        const data = where.accountId_resource_resourceId_stateKey; states.set(keyOf(data), update.value ?? create.value); return { ...create, value: states.get(keyOf(data)) };
      }),
    },
    userPreference: {
      findMany: jest.fn(async () => []),
      upsert: jest.fn(async () => ({})),
    },
    resourceCache: { deleteMany: jest.fn(async () => ({ count: 2 })) },
  };

  beforeAll(() => { originalProvider = process.env.EDUFLOW_PROVIDER; process.env.EDUFLOW_PROVIDER = "fake"; });
  afterAll(() => { if (originalProvider === undefined) delete process.env.EDUFLOW_PROVIDER; else process.env.EDUFLOW_PROVIDER = originalProvider; });
  beforeEach(() => { states.clear(); jest.clearAllMocks(); service = new DemoSchoolService(prisma as never); });

  it("keeps message search, type filters and pagination behavior", async () => {
    const page = await service.messages({ sub: "acct", jti: "t", tokenUse: "access" }, { type: "sprava", q: "MS BERGER parent-teacher", limit: "1" });
    expect(page.total).toBe(1);
    expect(page.items[0]).toMatchObject({ id: 4101, type_label: "Message" });
    await expect(service.messages({ sub: "acct", jti: "t", tokenUse: "access" }, { type: "bogus" })).rejects.toMatchObject({ response: { code: "VALIDATION" } });
  });

  it("filters, counts and changes homework state in PostgreSQL-backed local state", async () => {
    const claims = { sub: "acct", jti: "t", tokenUse: "access" as const };
    const list = await service.homework(claims, { include_tests: "0" });
    expect(list.total).toBe(4);
    expect(list.counts).toEqual({ offen: 2, ueberfaellig: 1, erledigt: 1, papierkorb: 0 });
    const updated = await service.homeworkChange(claims, "5101", "done", { done: true });
    expect(updated).toMatchObject({ id: 5101, is_done: true, status: "erledigt" });
    expect((await service.homework(claims, { status: "erledigt" })).items.map((item) => item.id)).toContain(5101);
    const hidden = await service.homeworkChange(claims, "5102", "trash", { hide: true });
    expect(hidden.is_hidden).toBe(true);
    expect((await service.homework(claims, { status: "papierkorb" })).total).toBe(1);
  });

  it("preserves the mobile settings schema and normalizes values", async () => {
    const claims = { sub: "acct", jti: "t", tokenUse: "access" as const };
    const current = await service.settings(claims);
    expect(current.values.landing).toBe("uebersicht");
    expect(current.schema[0]?.options).toEqual([["uebersicht", "Overview"], ["dashboard", "Messages"], ["hausaufgaben", "Homework"], ["noten", "Grades"], ["stundenplan", "Timetable"]]);
    const saved = await service.saveSettings(claims, { landing: "invalid", ov_unread: 999, hw_tests: true, wetter_city: "  Wien  " });
    expect(saved.values).toMatchObject({ landing: "uebersicht", ov_unread: 50, hw_tests: true, wetter_city: "Wien" });
  });

  it("returns five school days, agenda, grades and demo weather", () => {
    const week = service.timetableWeek({ day: "2026-09-24" });
    expect(week.days).toHaveLength(5);
    expect(week.days[0]?.day_name).toBe("Monday");
    expect(service.timetableDay({ day: "2026-09-25" }).lessons).toHaveLength(4);
    expect(service.timetableDay({ day: "2026-09-26" }).lessons).toHaveLength(0);
    expect(service.agenda({}).items.map((item) => item.kind)).toEqual(expect.arrayContaining(["event", "exam", "attendance"]));
    expect(service.grades({ limit: "1" }).items).toHaveLength(1);
    expect(service.weather({ city: "Wien" }).city).toBe("Wien");
    expect(service.searchCities("Mün").items[0]?.name).toBe("München");
  });
});
