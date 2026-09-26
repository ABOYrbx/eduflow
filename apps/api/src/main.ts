import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { resolve } from "node:path";
import { ApiExceptionFilter } from "./common/api-exception.filter";

async function bootstrap(): Promise<void> {
  // Resolve configuration relative to this API package so startup behaves the
  // same from the repository root and from apps/api.
  for (const path of [resolve(__dirname, "../.env.local"), resolve(__dirname, "../.env")]) {
    try {
      process.loadEnvFile(path);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
  }
  // Import only after environment files so module-level config sees them.
  const { AppModule } = await import("./app.module");
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  app.setGlobalPrefix("api/v1");
  app.useGlobalFilters(new ApiExceptionFilter());
  const port = Number(process.env.PORT ?? "8000");
  await app.listen(port, "127.0.0.1");
}

void bootstrap();
