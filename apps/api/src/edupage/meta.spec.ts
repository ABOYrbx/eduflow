import { aggregateDay, getWetter, owmCap, owmCompass, owmLocaltime, pyRound, searchWetterCities, FetchJson } from "./meta";

const okFetch = (current: unknown, forecast: unknown): FetchJson => async (url) => ({
  status: 200,
  json: url.includes("/forecast") ? forecast : current,
});

const FORECAST = {
  city: { timezone: 3600 },
  list: [
    { dt_txt: "2026-09-17 09:00:00", dt: 1789606800, main: { temp: 14.2 }, weather: [{ icon: "02d", description: "leicht bewölkt" }], pop: 0.1 },
    { dt_txt: "2026-09-17 12:00:00", dt: 1789617600, main: { temp: 18.6 }, weather: [{ icon: "01d", description: "klarer himmel" }], pop: 0 },
    { dt_txt: "2026-09-17 15:00:00", dt: 1789628400, main: { temp: 17.1 }, weather: [{ icon: "01d", description: "klarer himmel" }], pop: 0.2 },
    { dt_txt: "2026-09-18 12:00:00", dt: 1789704000, main: { temp: 16.4 }, weather: [{ icon: "10d", description: "leichter regen" }], pop: 0.8 },
  ],
};
const CURRENT = {
  cod: 200, name: "Berlin", timezone: 3600,
  weather: [{ description: "klarer himmel", icon: "01d" }],
  main: { temp: 15.4, temp_max: 16.1, temp_min: 13.9, feels_like: 14.8, humidity: 60, pressure: 1015 },
  wind: { speed: 3.5, deg: 90 },
  clouds: { all: 10 },
  visibility: 10000,
  sys: { sunrise: 1789584000, sunset: 1789630800 },
};

describe("meta (Port von app.py-Wetter, Paket N-G)", () => {
  it("rundet, kappt und kompasst wie Python", () => {
    expect(pyRound(2.5)).toBe(2);
    expect(pyRound(3.5)).toBe(4);
    expect(pyRound(2.674, 2)).toBe(2.67);
    expect(owmCap("klarer himmel")).toBe("Klarer himmel");
    expect(owmCompass(90)).toBe("O");
    expect(owmCompass("x")).toBe("–");
    expect(owmLocaltime(1789646400, 3600)).toBe("13:00");
    expect(owmLocaltime("x", 0)).toBe("–");
  });

  it("aggregiert Tageswerte mit Mittagsbevorzugung", () => {
    const today = new Date(2026, 8, 16, 12, 0, 0);
    expect(aggregateDay(FORECAST, 1, today)).toMatchObject({ max: 19, min: 14, desc: "Klarer himmel", icon: "01d", pop: 20 });
    expect(aggregateDay(FORECAST, 5, today)).toBeNull();
  });

  it("baut das Wetter-Payload wie Python", async () => {
    const today = new Date(2026, 8, 16, 12, 0, 0);
    const { payload, status } = await getWetter(okFetch(CURRENT, FORECAST), "key", 52.5, 13.4, "", today);
    expect(status).toBe(200);
    expect(payload).toMatchObject({ city: "Berlin" });
    const typed = payload as { today: Record<string, unknown>; tomorrow: Record<string, unknown>; day3: Record<string, unknown>; hourly: unknown[]; details: Record<string, unknown> };
    expect(typed.today).toMatchObject({ temp: 15, max: 16, min: 14, desc: "Klarer himmel", icon: "01d" });
    expect(typed.tomorrow).toMatchObject({ max: 19, min: 14 });
    expect(typed.day3).toMatchObject({ label: "Freitag" });
    expect(typed.hourly).toHaveLength(4);
    expect(typed.details).toMatchObject({ feels_like: 15, humidity: 60, wind_kmh: 13, wind_dir: "O", visibility_km: 10 });
  });

  it("meldet fehlenden Ort/Schlüssel/Upstream wie Python", async () => {
    await expect(getWetter(okFetch(CURRENT, FORECAST), "key", null, null, "")).resolves.toMatchObject({ status: 400 });
    await expect(getWetter(okFetch(CURRENT, FORECAST), "", 52.5, 13.4, "")).resolves.toMatchObject({ payload: { error: "Kein API-Key (OPENWEATHER_KEY in .env eintragen)" }, status: 503 });
    await expect(getWetter(okFetch({ cod: 404, message: "city not found" }, FORECAST), "key", 0, 0, "")).resolves.toMatchObject({ payload: { error: "city not found" }, status: 502 });
    const failing: FetchJson = async () => { throw new Error("netz weg"); };
    await expect(getWetter(failing, "key", 0, 0, "")).resolves.toMatchObject({ payload: { error: "netz weg" }, status: 502 });
  });

  it("sucht Städte mit Deduplizierung", async () => {
    const geo: FetchJson = async () => ({ status: 200, json: [{ name: "Berlin", state: "", country: "DE" }, { name: "Berlin", state: "Berlin", country: "DE" }, { name: "", country: "XX" }] });
    const { payload, status } = await searchWetterCities(geo, "key", "berlin");
    expect(status).toBe(200);
    expect(payload).toEqual({ items: [
      { name: "Berlin", state: "", country: "DE", label: "Berlin · DE", query: "Berlin, DE" },
      { name: "Berlin", state: "Berlin", country: "DE", label: "Berlin · DE", query: "Berlin, DE" },
    ] });
    await expect(searchWetterCities(geo, "key", "x")).resolves.toEqual({ payload: { items: [] }, status: 200 });
    await expect(searchWetterCities(geo, "", "berlin")).resolves.toMatchObject({ status: 503 });
    const broken: FetchJson = async () => ({ status: 500, json: {} });
    await expect(searchWetterCities(broken, "key", "berlin")).resolves.toMatchObject({ status: 502 });
  });
});
