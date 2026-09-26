import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { SchoolController } from "./school.controller";
import { DemoSchoolService } from "./demo-school.service";

@Module({ imports: [AuthModule], controllers: [SchoolController], providers: [DemoSchoolService] })
export class SchoolModule {}
