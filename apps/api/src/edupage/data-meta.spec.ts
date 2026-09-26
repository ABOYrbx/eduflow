import { EdupageDataService } from "./data";
import type { FetchBytes } from "./essen";

const MENU_TEXT = "Speisekarte Montag 14.9. bis Freitag 18.9.2026\nMontag: Suppe 3,50 €\nDienstag: Nudeln 5,20 €\n";

describe("EdupageDataService (Paket N-G, Python-Parität)", () => {
  const oldKey = process.env.OPENWEATHER_KEY;
  const prisma = {
    userAccount: { findUnique: jest.fn(async () => null) },
    credentialVault: { findUnique: jest.fn(async () => null) },
    resourceCache: { findUnique: jest.fn(async () => null), findMany: jest.fn(async () => []), upsert: jest.fn(async () => ({})), deleteMany: jest.fn(async () => ({ count: 0 })) },
    localResourceState: { findUnique: jest.fn(async () => null), findMany: jest.fn(async () => []), upsert: jest.fn(async () => ({})), create: jest.fn(async () => ({})), deleteMany: jest.fn(async () => ({ count: 0 })) },
    userPreference: { findMany: jest.fn(async () => []), upsert: jest.fn(async () => ({})) },
    pendingSecondFactor: { create: jest.fn(), findUnique: jest.fn(), updateMany: jest.fn() },
    apiToken: { create: jest.fn(), findUnique: jest.fn(), findMany: jest.fn(async () => []), update: jest.fn(), updateMany: jest.fn(async () => ({ count: 0 })) },
  };

  beforeEach(() => {
    jest.clearAllMocks();
    delete process.env.OPENWEATHER_KEY;
  });
  afterAll(() => {
    if (oldKey === undefined) delete process.env.OPENWEATHER_KEY;
    else process.env.OPENWEATHER_KEY = oldKey;
  });

  const withMenu = (fetchBytes: FetchBytes) =>
    new EdupageDataService(prisma as never, undefined, { fetchBytes, extractPdfText: async () => MENU_TEXT });

  it("lädt Essen frisch, aus dem Cache und offline wie Python", async () => {
    const seen: string[] = [];
    const serviceWithPdf = withMenu(async (url: string) => {
      seen.push(url);
      return url.includes("/2026/09/") ? Buffer.from("%PDF-1.4 daten") : null;
    });
    const today = new Date(2026, 8, 16, 12, 0, 0);
    const fresh = await serviceWithPdf.essenMenu({}, today) as unknown as { week: string; cached: boolean; cache_info: string; source_url: string };
    expect(fresh).toMatchObject({ week: "2026-W38", cached: false, cache_info: "frisch geladen" });
    expect(fresh.source_url).toContain("38.-KW.pdf");
    const cached = await serviceWithPdf.essenMenu({}, today) as unknown as { cached: boolean; cache_info: string };
    expect(cached.cached).toBe(true);
    expect(cached.cache_info).toMatch(/^aus Cache/);
    expect(seen).toHaveLength(1);
    const forced = await serviceWithPdf.essenMenu({ refresh: "1" }, today) as unknown as { cached: boolean };
    expect(forced.cached).toBe(false);
    const offline = withMenu(async () => null);
    await expect(offline.essenMenu({}, today)).rejects.toMatchObject({ response: { code: "UPSTREAM" } });
  });

  it("validiert Wetter-Anfragen und mappt Fehler wie Python", async () => {
    const json = async (url: string) => {
      void url;
      return { status: 200, json: { cod: 200, name: "X", timezone: 0, weather: [{ description: "klar", icon: "01d" }], main: { temp: 10, temp_max: 11, temp_min: 9 }, wind: {}, clouds: {}, sys: {} } };
    };
    const weatherService = new EdupageDataService(prisma as never, undefined, { fetchJson: json });
    await expect(weatherService.weather({})).rejects.toMatchObject({ response: { error: "Bitte Koordinaten (?lat=..&lon=..) oder Stadt (?city=..) angeben.", code: "VALIDATION" } });
    await expect(weatherService.weather({ lat: "52", lon: "13" })).rejects.toMatchObject({ response: { code: "CONFIG_MISSING" } });
    process.env.OPENWEATHER_KEY = "key";
    const ok = await weatherService.weather({ city: "Berlin" }) as unknown as { city: string };
    expect(ok.city).toBe("X");
    await expect(weatherService.searchCities("x")).resolves.toEqual({ items: [] });
    delete process.env.OPENWEATHER_KEY;
    await expect(weatherService.searchCities("ber")).rejects.toMatchObject({ response: { code: "CONFIG_MISSING" } });
  });
});
