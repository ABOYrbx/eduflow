/** Wetter-Proxy (Port von `app.py`, Paket N-G). Key bleibt serverseitig. */
import { t } from "../i18n";

export type FetchJson = (url: string, params: Record<string, string>, timeoutMs: number) => Promise<{ status: number; json: unknown }>;

/** Runden wie Python (`round`, half-even) für identische Anzeigewerte. */
export function pyRound(value: number, ndigits = 0): number {
  const factor = 10 ** ndigits;
  const scaled = value * factor;
  const floor = Math.floor(scaled);
  const diff = scaled - floor;
  const rounded = diff < 0.5 ? floor : diff > 0.5 ? floor + 1 : (floor % 2 === 0 ? floor : floor + 1);
  return rounded / factor;
}

/** Nur ersten Buchstaben groß (Port von `_owm_cap`). */
export function owmCap(value: unknown): string {
  const text = typeof value === "string" ? value : "";
  return text ? text.slice(0, 1).toUpperCase() + text.slice(1) : "";
}

/** Unix-Zeit + Offset → lokale HH:MM (Port von `_owm_localtime`). */
export function owmLocaltime(ts: unknown, tzOffset: unknown): string {
  try {
    const date = new Date((Number(ts) + Number(tzOffset)) * 1000);
    if (Number.isNaN(date.getTime())) return "–";
    const pad = (value: number): string => String(value).padStart(2, "0");
    return `${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}`;
  } catch {
    return "–";
  }
}

/** Windrichtung in Grad → Himmelsrichtung (Port von `_owm_compass`). */
export function owmCompass(deg: unknown): string {
  try {
    const dirs = ["N", "NO", "O", "SO", "S", "SW", "W", "NW"];
    const index = Math.floor((Number(deg) + 22.5) / 45);
    if (!Number.isFinite(index)) return "–";
    return dirs[((index % 8) + 8) % 8] ?? "–";
  } catch {
    return "–";
  }
}

interface ForecastEntry {
  dt_txt?: unknown;
  dt?: unknown;
  main?: { temp?: unknown };
  weather?: Array<{ icon?: unknown; description?: unknown }>;
  pop?: unknown;
}

const asRecord = (value: unknown): Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : {};

/** Tageswerte aus der 3-Stunden-Vorhersage (Port von `_owm_aggregate_day`). */
export function aggregateDay(forecast: unknown, dayOffset: number, today = new Date()): Record<string, unknown> | null {
  const base = new Date(today.getTime() + dayOffset * 86400000);
  const pad = (value: number): string => String(value).padStart(2, "0");
  const day = `${base.getFullYear()}-${pad(base.getMonth() + 1)}-${pad(base.getDate())}`;
  const list = asRecord(forecast).list;
  const entries = (Array.isArray(list) ? list : []).filter((entry): entry is ForecastEntry => {
    const record = entry as Record<string, unknown>;
    return typeof record === "object" && record !== null && String((record as ForecastEntry).dt_txt ?? "").startsWith(day);
  });
  const temps = entries.map((entry) => entry.main?.temp).filter((temp): temp is number => typeof temp === "number");
  if (!temps.length) return null;
  const conds = entries.map((entry) => entry.weather?.[0] ?? {});
  const midday = entries.map((entry, index) => ({ entry, cond: conds[index] ?? {} }))
    .filter(({ entry, cond }) => String(entry.dt_txt ?? "").includes("12:00:00") && cond.icon);
  let icon = "";
  let desc = "";
  if (midday.length > 0) {
    icon = String(midday[0]?.cond.icon ?? "");
    desc = String(midday[0]?.cond.description ?? "");
  } else {
    const icons = conds.map((cond) => cond.icon).filter((value): value is string => typeof value === "string" && !!value);
    const counts = new Map<string, number>();
    for (const value of icons) counts.set(value, (counts.get(value) ?? 0) + 1);
    let best = "";
    let bestCount = 0;
    for (const [value, count] of counts) {
      if (count > bestCount) { best = value; bestCount = count; }
    }
    icon = best;
    desc = String(conds.find((cond) => cond.icon === icon)?.description ?? "");
  }
  const pops = entries.map((entry) => entry.pop).filter((pop): pop is number => typeof pop === "number");
  return {
    max: pyRound(Math.max(...temps)),
    min: pyRound(Math.min(...temps)),
    desc: owmCap(desc),
    icon: icon || "",
    pop: pops.length ? pyRound(Math.max(...pops) * 100) : null,
  };
}

const defaultFetchJson: FetchJson = async (url, params, timeoutMs) => {
  const target = new URL(url);
  for (const [key, value] of Object.entries(params)) target.searchParams.append(key, value);
  const response = await fetch(target.toString(), { signal: AbortSignal.timeout(timeoutMs) });
  return { status: response.status, json: await response.json() as unknown };
};

const numOrNull = (value: unknown): number | null => (typeof value === "number" && Number.isFinite(value) ? value : null);

/** Wetter laden und aufbereiten (Port von `get_wetter_payload`). */
export async function getWetter(fetchJson: FetchJson, key: string, lat: number | null, lon: number | null, city: string, today = new Date()): Promise<{ payload: Record<string, unknown>; status: number }> {
  const params: Record<string, string> = { appid: key, units: "metric", lang: "de" };
  if (lat !== null && lon !== null) {
    params.lat = String(lat);
    params.lon = String(lon);
  } else if (city) {
    params.q = city;
  } else {
    return { payload: { error: t("geo.badCoords") }, status: 400 };
  }
  if (!key) return { payload: { error: t("geo.noKey") }, status: 503 };
  let cur: Record<string, unknown>;
  let forecast: Record<string, unknown>;
  try {
    const current = await fetchJson("https://api.openweathermap.org/data/2.5/weather", params, 8000);
    cur = asRecord(current.json);
    if (String(cur.cod ?? "") !== "200") return { payload: { error: typeof cur.message === "string" ? cur.message : "upstream" }, status: 502 };
    const coming = await fetchJson("https://api.openweathermap.org/data/2.5/forecast", params, 8000);
    forecast = asRecord(coming.json);
  } catch (error) {
    return { payload: { error: error instanceof Error ? error.message : String(error) }, status: 502 };
  }
  const weather0 = (Array.isArray(cur.weather) ? cur.weather[0] : {}) as Record<string, unknown>;
  const main = asRecord(cur.main);
  const wind = asRecord(cur.wind);
  const sys = asRecord(cur.sys);
  const cityInfo = asRecord(forecast.city);
  let tz: unknown = cityInfo.timezone ?? cur.timezone ?? 0;
  if (typeof tz !== "number" || !Number.isFinite(tz)) tz = 0;
  const tomorrow = aggregateDay(forecast, 1, today) ?? {};
  const day3 = aggregateDay(forecast, 2, today) ?? {};
  const weekdays = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"];
  const inTwo = new Date(today.getTime() + 2 * 86400000);
  day3.label = weekdays[(inTwo.getDay() + 6) % 7];
  const todayPop = aggregateDay(forecast, 0, today);
  const hourly: Record<string, unknown>[] = [];
  const list = Array.isArray(forecast.list) ? forecast.list : [];
  for (const raw of list.slice(0, 8)) {
    if (typeof raw !== "object" || raw === null) continue;
    const entry = raw as Record<string, unknown>;
    const cond = (Array.isArray(entry.weather) ? entry.weather[0] : {}) as Record<string, unknown>;
    const entryMain = asRecord(entry.main);
    hourly.push({
      time: owmLocaltime(entry.dt, tz),
      temp: typeof entryMain.temp === "number" ? pyRound(entryMain.temp) : null,
      icon: typeof cond.icon === "string" ? cond.icon : "",
      desc: owmCap(typeof cond.description === "string" ? cond.description : ""),
      pop: typeof entry.pop === "number" ? pyRound(entry.pop * 100) : null,
    });
  }
  const windMs = numOrNull(wind.speed);
  const visM = numOrNull(cur.visibility);
  const clouds = asRecord(cur.clouds);
  const temp = numOrNull(main.temp) ?? 0;
  return {
    payload: {
      city: typeof cur.name === "string" ? cur.name : "",
      today: {
        temp: pyRound(temp),
        max: pyRound(numOrNull(main.temp_max) ?? temp),
        min: pyRound(numOrNull(main.temp_min) ?? temp),
        desc: owmCap(typeof weather0.description === "string" ? weather0.description : ""),
        icon: typeof weather0.icon === "string" ? weather0.icon : "",
        pop: todayPop ? todayPop.pop ?? null : null,
      },
      tomorrow,
      day3,
      hourly,
      details: {
        feels_like: typeof main.feels_like === "number" ? pyRound(main.feels_like) : null,
        humidity: numOrNull(main.humidity),
        pressure: numOrNull(main.pressure),
        wind_kmh: windMs !== null ? pyRound(windMs * 3.6) : null,
        wind_dir: owmCompass(wind.deg),
        clouds: numOrNull(clouds.all),
        visibility_km: visM !== null ? pyRound(visM / 1000, 1) : null,
        sunrise: owmLocaltime(sys.sunrise, tz),
        sunset: owmLocaltime(sys.sunset, tz),
      },
    },
    status: 200,
  };
}

/** Stadtsuche (Port von `search_wetter_cities`). */
export async function searchWetterCities(fetchJson: FetchJson, key: string, query: string): Promise<{ payload: Record<string, unknown>; status: number }> {
  const text = String(query ?? "").trim().slice(0, 100);
  if (text.length < 2) return { payload: { items: [] }, status: 200 };
  if (!key) return { payload: { error: t("geo.citySetup") }, status: 503 };
  try {
    const response = await fetchJson("https://api.openweathermap.org/geo/1.0/direct", { q: text, limit: "5", appid: key }, 5000);
    if (response.status !== 200 || !Array.isArray(response.json)) {
      return { payload: { error: t("geo.citySearch") }, status: 502 };
    }
    const items: Record<string, unknown>[] = [];
    for (const raw of response.json.slice(0, 5)) {
      if (typeof raw !== "object" || raw === null) continue;
      const place = raw as Record<string, unknown>;
      const name = typeof place.name === "string" ? place.name.trim() : "";
      const country = typeof place.country === "string" ? place.country.trim() : "";
      const state = typeof place.state === "string" ? place.state.trim() : "";
      if (!name) continue;
      const parts: string[] = [];
      for (const part of [name, state, country]) {
        if (part && !parts.some((existing) => existing.toLowerCase() === part.toLowerCase())) parts.push(part);
      }
      items.push({ name, state, country, label: parts.join(" · "), query: parts.join(", ").slice(0, 100) });
    }
    return { payload: { items }, status: 200 };
  } catch {
    return { payload: { error: t("geo.citySearch") }, status: 502 };
  }
}

export { defaultFetchJson };
