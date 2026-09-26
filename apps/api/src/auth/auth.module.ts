import { Module } from "@nestjs/common";
import { JwtModule } from "@nestjs/jwt";
import { AuthController } from "./auth.controller";
import { AuthService } from "./auth.service";
import { AccessTokenGuard } from "./access-token.guard";

const jwtSecret = process.env.JWT_ACCESS_SECRET ?? "local-development-only-rotate-this-secret-32-bytes";

@Module({
  imports: [JwtModule.register({ secret: jwtSecret })],
  controllers: [AuthController],
  providers: [AuthService, AccessTokenGuard],
  exports: [AccessTokenGuard, AuthService],
})
export class AuthModule {}
