import { Test } from "@nestjs/testing";
import { SystemController } from "./system.controller";

describe("SystemController", () => {
  it("reports v1 health without upstream or database dependencies", async () => {
    const module = await Test.createTestingModule({ controllers: [SystemController] }).compile();
    expect(module.get(SystemController).health()).toEqual({ status: "ok", version: "v1" });
  });

  it("publishes every legacy API route in the compatibility contract", async () => {
    const module = await Test.createTestingModule({ controllers: [SystemController] }).compile();
    const document = module.get(SystemController).openapi() as {
      openapi: string;
      paths: Record<string, Record<string, unknown>>;
    };
    expect(document.openapi).toBe("3.0.0");
    // Vollständige Pfadliste aus Python (`api/__init__.py` + Ressourcen-Pakete).
    const legacyPaths = [
      "/api/v1/auth/2fa",
      "/api/v1/auth/login",
      "/api/v1/auth/logout",
      "/api/v1/auth/refresh",
      "/api/v1/cache-clear",
      "/api/v1/devices",
      "/api/v1/devices/{id}",
      "/api/v1/grades",
      "/api/v1/health",
      "/api/v1/homework",
      "/api/v1/homework/{id}/done",
      "/api/v1/homework/{id}/trash",
      "/api/v1/me",
      "/api/v1/messages",
      "/api/v1/messages/{id}/attachments/{idx}",
      "/api/v1/messages/{id}/reply",
      "/api/v1/messages/{id}/thread",
      "/api/v1/messages/download-token",
      "/api/v1/messages/read",
      "/api/v1/messages/send",
      "/api/v1/openapi.json",
      "/api/v1/recipients",
      "/api/v1/school/agenda",
      "/api/v1/settings",
      "/api/v1/substitutions/week",
      "/api/v1/timetable/day",
      "/api/v1/timetable/week",
      "/api/v1/wetter",
      "/api/v1/wetter/suche",
    ];
    expect(Object.keys(document.paths)).toHaveLength(legacyPaths.length);
    for (const path of legacyPaths) {
      expect(document.paths[path]).toBeDefined();
    }
    expect(document.paths["/api/v1/health"]?.get).toBeDefined();
    expect(document.paths["/api/v1/auth/login"]?.post).toBeDefined();
    expect(document.paths["/api/v1/devices"]?.post).toBeDefined();
  });
});
