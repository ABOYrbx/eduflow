import { Controller, Get } from "@nestjs/common";

@Controller()
export class SystemController {
  @Get("health")
  health(): { status: "ok"; version: "v1" } {
    return { status: "ok", version: "v1" };
  }

  @Get("openapi.json")
  openapi(): Record<string, unknown> {
    const get = (summary: string, secure = true) => ({ summary, responses: { "200": { description: "OK" }, "400": { description: "Validierungsfehler" }, "401": { description: "Authentifizierungsfehler" } }, ...(secure ? { security: [{ bearerAuth: [] }] } : {}) });
    const post = (summary: string, secure = true) => ({ ...get(summary, secure), requestBody: { required: false, content: { "application/json": { schema: { type: "object" } } } } });
    const paths: Record<string, unknown> = {
      "/api/v1/health": { get: get("Liveness-Probe", false) }, "/api/v1/openapi.json": { get: get("API-Vertrag", false) },
      "/api/v1/auth/login": { post: post("Anmelden", false) }, "/api/v1/auth/2fa": { post: post("Zwei-Faktor-Anmeldung abschließen", false) },
      "/api/v1/auth/logout": { post: post("Abmelden") }, "/api/v1/auth/refresh": { post: post("JWT-Token rotieren", false) },
      "/api/v1/me": { get: get("Eigenes Konto") }, "/api/v1/devices": { get: get("Eigene Geräte"), post: post("Geräte-Token erstellen") }, "/api/v1/devices/{id}": { delete: get("Gerät widerrufen") },
      "/api/v1/messages": { get: get("Nachrichtenliste") }, "/api/v1/messages/{id}/thread": { get: get("Nachrichtenthread") },
      "/api/v1/messages/read": { post: post("Nachrichten als gelesen markieren") }, "/api/v1/recipients": { get: get("Empfängerliste") },
      "/api/v1/messages/send": { post: post("Nachricht senden") }, "/api/v1/messages/{id}/reply": { post: post("Auf Nachricht antworten") },
      "/api/v1/messages/download-token": { post: post("Kurzzeit-Download-Token ausstellen") }, "/api/v1/messages/{id}/attachments/{idx}": { get: get("Nachrichtenanhang laden") },
      "/api/v1/homework": { get: get("Hausaufgabenliste") }, "/api/v1/homework/{id}/done": { post: post("Aufgabe erledigen oder öffnen") },
      "/api/v1/homework/{id}/trash": { post: post("Aufgabe in Papierkorb legen oder wiederherstellen") },
      "/api/v1/timetable/day": { get: get("Tagesstundenplan") }, "/api/v1/timetable/week": { get: get("Wochenstundenplan") },
      "/api/v1/substitutions/week": { get: get("Vertretungsplan") }, "/api/v1/school/agenda": { get: get("Schultermine, Prüfungen und Anwesenheit") },
      "/api/v1/grades": { get: get("Noten") },
      "/api/v1/wetter": { get: get("Wetter") }, "/api/v1/wetter/suche": { get: get("Wetter-Ortssuche") },
      "/api/v1/settings": { get: get("Einstellungen lesen"), put: post("Einstellungen speichern") }, "/api/v1/cache-clear": { post: post("Cache leeren") },
    };
    return { openapi: "3.0.0", info: { title: "EduFlow API", version: "v1" }, servers: [{ url: "/api/v1" }], components: { securitySchemes: { bearerAuth: { type: "http", scheme: "bearer" } } }, paths };
  }
}
