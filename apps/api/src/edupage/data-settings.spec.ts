import { EdupageDataService } from "./data";
import { SETTINGS_DEFAULTS, SETTINGS_SCHEMA, coerceSetting, settingsFromForm } from "./settings";

const claims = { sub: "acct_9", jti: "row_0", tokenUse: "access" as const };

describe("settings (Port von app.py + api/settings.py, Paket N-F)", () => {
  let prefs: Map<string, unknown>;
  let service: EdupageDataService;

  const prisma = {
    userAccount: { findUnique: jest.fn(async () => null) },
    credentialVault: { findUnique: jest.fn(async () => null) },
    resourceCache: {
      findUnique: jest.fn(async () => null),
      findMany: jest.fn(async () => []),
      upsert: jest.fn(async () => ({})),
      deleteMany: jest.fn(async () => ({ count: 2 })),
    },
    userPreference: {
      findMany: jest.fn(async () => [...prefs.entries()].map(([key, value]) => ({ key, value }))),
      upsert: jest.fn(async ({ create }: { create: { key: string; value: unknown } }) => { prefs.set(create.key, create.value); return {}; }),
    },
    localResourceState: { findUnique: jest.fn(async () => null), findMany: jest.fn(async () => []), upsert: jest.fn(async () => ({})), create: jest.fn(async () => ({})), deleteMany: jest.fn(async () => ({ count: 0 })) },
    pendingSecondFactor: { create: jest.fn(), findUnique: jest.fn(), updateMany: jest.fn() },
    apiToken: { create: jest.fn(), findUnique: jest.fn(), findMany: jest.fn(async () => []), update: jest.fn(), updateMany: jest.fn(async () => ({ count: 0 })) },
  };

  beforeEach(() => {
    prefs = new Map();
    jest.clearAllMocks();
    service = new EdupageDataService(prisma as never);
  });

  it("liefert Schema und Defaults wie Python", async () => {
    const got = await service.settingsGet(claims);
    expect(got.schema).toHaveLength(8);
    expect(got.values).toMatchObject({ landing: "uebersicht", hw_tests: false, ov_unread: 10, ov_order: "messages,homework,weather" });
    expect(SETTINGS_DEFAULTS.ov_wetter).toBe(true);
  });

  it("koerzt gespeicherte Werte wie _coerce_setting", async () => {
    prefs.set("landing", "dashboard");
    prefs.set("ov_unread", "999");
    prefs.set("hw_tests", "on");
    prefs.set("ov_order", "weather,weather,news");
    const got = await service.settingsGet(claims) as unknown as { values: Record<string, unknown> };
    expect(got.values).toMatchObject({ landing: "dashboard", ov_unread: 50, hw_tests: true, ov_order: "weather,messages,homework" });
  });

  it("speichert gegen Schema validiert wie Python", async () => {
    await expect(service.settingsPut(claims, null)).rejects.toMatchObject({ response: { error: "Ungültige Anfrage (JSON-Objekt erwartet)." } });
    const saved = await service.settingsPut(claims, { landing: "noten", hw_tests: true, ov_unread: "7", wetter_city: "  Berlin\n" }) as unknown as { values: Record<string, unknown> };
    expect(saved.values).toMatchObject({ landing: "noten", hw_tests: true, ov_unread: 7, wetter_city: "Berlin" });
    const reread = await service.settingsGet(claims) as unknown as { values: Record<string, unknown> };
    expect(reread.values.landing).toBe("noten");
  });

  it("leert den Cache ohne Einstellungen", async () => {
    await expect(service.cacheClear(claims)).resolves.toEqual({ status: "ok", cleared: 2 });
    expect(prisma.resourceCache.deleteMany).toHaveBeenCalledWith({ where: { accountId: claims.sub } });
  });

  it("koerzt Einzelwerte wie Python", () => {
    const select = SETTINGS_SCHEMA[0];
    if (!select) throw new Error("kein Schema");
    expect(coerceSetting(select, "dashboard")).toBe("dashboard");
    expect(coerceSetting(select, "falsch")).toBe("uebersicht");
    expect(settingsFromForm({})).toMatchObject({ landing: "uebersicht", hw_tests: false });
  });
});
