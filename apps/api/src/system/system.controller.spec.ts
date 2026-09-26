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
    expect(Object.keys(document.paths)).toHaveLength(30);
    for (const path of [
      "/api/v1/auth/login",
      "/api/v1/auth/2fa",
      "/api/v1/messages/{id}/attachments/{idx}",
      "/api/v1/homework/{id}/trash",
      "/api/v1/timetable/week",
      "/api/v1/substitutions/week",
      "/api/v1/school/agenda",
      "/api/v1/settings",
    ]) {
      expect(document.paths[path]).toBeDefined();
    }
    expect(document.paths["/api/v1/health"]?.get).toBeDefined();
    expect(document.paths["/api/v1/auth/login"]?.post).toBeDefined();
    expect(document.paths["/api/v1/devices"]?.post).toBeDefined();
  });
});
