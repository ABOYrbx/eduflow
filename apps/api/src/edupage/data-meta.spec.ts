import { EdupageDataService } from "./data";

describe("EdupageDataService (Paket N-G: Wetter, Python-Parität)", () => {
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
