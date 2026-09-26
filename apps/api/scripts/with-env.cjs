"use strict";

const { spawnSync } = require("node:child_process");
const path = require("node:path");

for (const envPath of [path.resolve(__dirname, "../.env.local"), path.resolve(__dirname, "../.env")]) {
  try {
    process.loadEnvFile(envPath);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
}

const [command, ...args] = process.argv.slice(2);
if (!command) {
  process.stderr.write("Es wurde kein Datenbankbefehl angegeben.\n");
  process.exit(2);
}

const result = spawnSync(command, args, { stdio: "inherit", env: process.env });
if (result.error) {
  process.stderr.write("Datenbankbefehl konnte nicht gestartet werden.\n");
  process.exit(1);
}
process.exit(result.status ?? 1);
