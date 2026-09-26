import { BadRequestException } from "@nestjs/common";
import { page, parsePage } from "./pagination";

const messageOf = (fn: () => unknown): string => {
  try {
    fn();
  } catch (error) {
    if (error instanceof BadRequestException) {
      expect(error.getStatus()).toBe(400);
      const body = error.getResponse() as Record<string, unknown>;
      expect(body.code).toBe("VALIDATION");
      return body.error as string;
    }
    throw error;
  }
  throw new Error("erwarteter VALIDATION-Fehler blieb aus");
};

describe("parsePage (Parität zu api/core.py)", () => {
  it("nutzt Standardwerte limit 50 und offset 0", () => {
    expect(parsePage({})).toEqual({ limit: 50, offset: 0 });
  });

  it("übernimmt gültige Werte und Grenzen", () => {
    expect(parsePage({ limit: "1", offset: "0" })).toEqual({ limit: 1, offset: 0 });
    expect(parsePage({ limit: "200", offset: "25" })).toEqual({ limit: 200, offset: 25 });
  });

  it("meldet nicht-ganze Zahlen wie Python", () => {
    expect(messageOf(() => parsePage({ limit: "viel" }))).toBe("Limit und Offset müssen ganze Zahlen sein.");
    expect(messageOf(() => parsePage({ offset: "2.5" }))).toBe("Limit und Offset müssen ganze Zahlen sein.");
    expect(messageOf(() => parsePage({ limit: "" }))).toBe("Limit und Offset müssen ganze Zahlen sein.");
    expect(messageOf(() => parsePage({ limit: "50.0" }))).toBe("Limit und Offset müssen ganze Zahlen sein.");
  });

  it("meldet Limit außerhalb 1..200 wie Python", () => {
    expect(messageOf(() => parsePage({ limit: "0" }))).toBe("Limit muss zwischen 1 und 200 liegen.");
    expect(messageOf(() => parsePage({ limit: "201" }))).toBe("Limit muss zwischen 1 und 200 liegen.");
    expect(messageOf(() => parsePage({ limit: "-5" }))).toBe("Limit muss zwischen 1 und 200 liegen.");
  });

  it("meldet negativen Offset wie Python", () => {
    expect(messageOf(() => parsePage({ offset: "-1" }))).toBe("Offset darf nicht negativ sein.");
  });
});

describe("page (Hüllobjekt wie api/core.py::page)", () => {
  it("schneidet items zu und behält total/limit/offset", () => {
    const items = [1, 2, 3, 4, 5];
    expect(page(items, { limit: "2", offset: "1" })).toEqual({ items: [2, 3], total: 5, limit: 2, offset: 1 });
    expect(page(items, { offset: "9" })).toEqual({ items: [], total: 5, limit: 50, offset: 9 });
  });
});
