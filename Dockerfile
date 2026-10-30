# syntax=docker/dockerfile:1
# EduFlow API (NestJS) — built from the repository root so npm workspaces
# (@eduflow/contracts) resolve correctly.
FROM node:22-bookworm AS deps
WORKDIR /app
COPY package.json package-lock.json .npmrc ./
COPY apps/api/package.json apps/api/
COPY apps/web/package.json apps/web/
COPY packages/contracts/package.json packages/contracts/
RUN npm ci

FROM node:22-bookworm AS build
WORKDIR /app
COPY --from=deps /app ./
COPY . .
RUN rm -f packages/contracts/tsconfig.tsbuildinfo apps/api/tsconfig.tsbuildinfo
RUN npm run build --workspace @eduflow/contracts
RUN npx prisma generate --schema apps/api/prisma/schema.prisma
RUN npm run build --workspace @eduflow/api

FROM node:22-bookworm AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/apps/api/node_modules ./apps/api/node_modules
COPY --from=build /app/packages/contracts/dist ./packages/contracts/dist
COPY --from=build /app/apps/api/dist ./apps/api/dist
COPY --from=build /app/apps/api/prisma ./apps/api/prisma
COPY --from=build /app/apps/api/package.json ./apps/api/package.json
COPY --from=build /app/package.json ./package.json
COPY docker/entrypoint.sh /usr/local/bin/eduflow-entrypoint
RUN chmod +x /usr/local/bin/eduflow-entrypoint
EXPOSE 3000
ENTRYPOINT ["eduflow-entrypoint"]