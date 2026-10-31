import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { SchoolController } from "./school.controller";
import { DemoSchoolService } from "./demo-school.service";
import { EdupageDataService } from "../edupage/data";
import { MessageSyncService } from "./message-sync.service";

@Module({ imports: [AuthModule], controllers: [SchoolController], providers: [DemoSchoolService, EdupageDataService, MessageSyncService] })
export class SchoolModule {}
