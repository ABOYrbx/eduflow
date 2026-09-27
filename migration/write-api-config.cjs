"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

function readFields() {
  const input = fs.readFileSync(0, "utf8").split("\0");
  if (input.at(-1) === "") input.pop();
  if (input.length !== 7) throw new Error("Ungültige Eingabe.");
  return input;
}

function encode(value) {
  return encodeURIComponent(value).replace(/[!'()*]/g, (character) =>
    `%${character.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

function dotenvQuote(value) {
  return JSON.stringify(value);
}

function main() {
  const [host, port, database, username, password, suppliedJwt, suppliedEncryptionKey] = readFields();
  if (!host || /[\s/@?#]/.test(host)) throw new Error("Ungültiger Datenbank-Host.");
  if (!/^\d{1,5}$/.test(port) || Number(port) < 1 || Number(port) > 65535) throw new Error("Ungültiger Datenbank-Port.");
  if (!database || !username) throw new Error("Datenbankname und Benutzer sind erforderlich.");

  const jwt = suppliedJwt || crypto.randomBytes(32).toString("base64url");
  if (Buffer.byteLength(jwt, "utf8") < 32) throw new Error("Der JWT-Schlüssel muss mindestens 32 Byte lang sein.");
  const encryptionKey = suppliedEncryptionKey || crypto.randomBytes(32).toString("hex");
  if (!/^[\da-fA-F]{64}$/.test(encryptionKey)) throw new Error("Der Verschlüsselungsschlüssel muss aus 64 Hex-Zeichen bestehen.");

  const hostname = host.includes(":") && !host.startsWith("[") ? `[${host}]` : host;
  const databaseUrl = `postgresql://${encode(username)}:${encode(password)}@${hostname}:${port}/${encode(database)}?schema=public`;
  const config = [
    `DATABASE_URL=${dotenvQuote(databaseUrl)}`,
    `PORT=${dotenvQuote("3000")}`,
    `JWT_ACCESS_SECRET=${dotenvQuote(jwt)}`,
    `CREDENTIAL_ENCRYPTION_KEY=${dotenvQuote(encryptionKey)}`,
    `EDUFLOW_PROVIDER=${dotenvQuote("edupage")}`,
    "",
  ].join("\n");

  const target = path.resolve("apps/api/.env.local");
  let descriptor;
  let created = false;
  try {
    descriptor = fs.openSync(target, "wx", 0o600);
    created = true;
    fs.writeFileSync(descriptor, config, { encoding: "utf8" });
    fs.fsyncSync(descriptor);
    fs.closeSync(descriptor);
    descriptor = undefined;
  } catch (error) {
    if (descriptor !== undefined) fs.closeSync(descriptor);
    if (created) {
      try {
        fs.unlinkSync(target);
      } catch {
        // Keep the original write error if cleanup is not possible.
      }
    }
    throw error;
  }
}

try {
  main();
} catch {
  process.stderr.write("Konfiguration konnte nicht sicher gespeichert werden. Prüfe Eingaben und Dateirechte.\n");
  process.exitCode = 1;
}
