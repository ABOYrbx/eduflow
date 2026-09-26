import { Module } from "@nestjs/common";
import { AuthModule } from "./auth/auth.module";
import { PrismaModule } from "./prisma/prisma.module";
import { SystemController } from "./system/system.controller";
import { SchoolModule } from "./school/school.module";

@Module({ imports: [PrismaModule, AuthModule, SchoolModule], controllers: [SystemController] })
export class AppModule {}
