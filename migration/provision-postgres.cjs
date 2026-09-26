"use strict";

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");

function readFields() {
  const input = fs.readFileSync(0, "utf8").split("\0");
  if (input.at(-1) === "") input.pop();
  if (input.length !== 4) throw new Error("Ungültige Eingabe.");
  return input;
}

function quoteIdentifier(value) {
  return `"${value.replaceAll('"', '""')}"`;
}

function quoteLiteral(value) {
  return `'${value.replaceAll("'", "''")}'`;
}

function runPsql(platform, sql) {
  const command = platform === "linux" ? "sudo" : "psql";
  const args = platform === "linux"
    ? ["-u", "postgres", "psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", "postgres"]
    : ["-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", "postgres"];
  const result = spawnSync(command, args, { input: sql, stdio: ["pipe", "ignore", "ignore"] });
  return !result.error && result.status === 0;
}

function runCreatedb(platform, username, database) {
  const command = platform === "linux" ? "sudo" : "createdb";
  const args = platform === "linux"
    ? ["-u", "postgres", "createdb", "--owner", username, database]
    : ["--owner", username, database];
  const result = spawnSync(command, args, { stdio: "ignore" });
  return !result.error && result.status === 0;
}

function main() {
  const [platform, username, database, password] = readFields();
  if (platform !== "macos" && platform !== "linux") throw new Error("Ungültige Plattform.");
  const safeName = /^[A-Za-z_][A-Za-z0-9_]{0,62}$/;
  if (!safeName.test(username) || !safeName.test(database)) throw new Error("Ungültiger Name.");
  if (!password) throw new Error("Leeres Passwort.");

  const preflight = `DO $$\nBEGIN\n` +
    `  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = ${quoteLiteral(username)}) THEN\n` +
    `    RAISE EXCEPTION 'Die Datenbankrolle ist bereits vorhanden.';\n` +
    `  END IF;\n` +
    `  IF EXISTS (SELECT 1 FROM pg_database WHERE datname = ${quoteLiteral(database)}) THEN\n` +
    `    RAISE EXCEPTION 'Die Datenbank ist bereits vorhanden.';\n` +
    `  END IF;\nEND $$;\n` +
    `CREATE ROLE ${quoteIdentifier(username)} LOGIN PASSWORD ${quoteLiteral(password)};\n`;

  if (!runPsql(platform, preflight)) throw new Error("PostgreSQL konnte die neue Rolle nicht anlegen.");
  if (!runCreatedb(platform, username, database)) {
    // The role belongs to this installer run; remove it if database creation failed.
    runPsql(platform, `DROP ROLE ${quoteIdentifier(username)};\n`);
    throw new Error("PostgreSQL konnte die neue Datenbank nicht anlegen.");
  }
}

try {
  main();
} catch {
  process.stderr.write("PostgreSQL konnte nicht automatisch eingerichtet werden. Prüfe Dienststatus, Rechte und ob Name oder Datenbank bereits existieren.\n");
  process.exitCode = 1;
}
