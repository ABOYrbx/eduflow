-- CreateTable
CREATE TABLE "UserAccount" (
    "id" TEXT NOT NULL,
    "subdomain" TEXT NOT NULL,
    "username" TEXT NOT NULL,
    "encryptedCredentials" BYTEA,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "UserAccount_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ApiToken" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "accessTokenHash" TEXT NOT NULL,
    "refreshTokenHash" TEXT,
    "deviceName" TEXT NOT NULL DEFAULT '',
    "accessExpiresAt" TIMESTAMP(3) NOT NULL,
    "refreshExpiresAt" TIMESTAMP(3),
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "rotatedFromId" TEXT,
    "lastUsedAt" TIMESTAMP(3),

    CONSTRAINT "ApiToken_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PendingSecondFactor" (
    "id" TEXT NOT NULL,
    "accountId" TEXT,
    "opaqueTokenHash" TEXT NOT NULL,
    "challenge" BYTEA NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "consumedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PendingSecondFactor_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UserPreference" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "value" JSONB NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "UserPreference_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LocalResourceState" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "resource" TEXT NOT NULL,
    "resourceId" TEXT NOT NULL,
    "stateKey" TEXT NOT NULL,
    "value" JSONB NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "LocalResourceState_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ResourceCache" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "cacheKey" TEXT NOT NULL,
    "payload" JSONB NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ResourceCache_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AuditEvent" (
    "id" TEXT NOT NULL,
    "accountId" TEXT,
    "action" TEXT NOT NULL,
    "outcome" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "UserAccount_subdomain_username_key" ON "UserAccount"("subdomain", "username");

-- CreateIndex
CREATE UNIQUE INDEX "ApiToken_accessTokenHash_key" ON "ApiToken"("accessTokenHash");

-- CreateIndex
CREATE UNIQUE INDEX "ApiToken_refreshTokenHash_key" ON "ApiToken"("refreshTokenHash");

-- CreateIndex
CREATE INDEX "ApiToken_accountId_revokedAt_idx" ON "ApiToken"("accountId", "revokedAt");

-- CreateIndex
CREATE INDEX "ApiToken_refreshExpiresAt_idx" ON "ApiToken"("refreshExpiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "PendingSecondFactor_opaqueTokenHash_key" ON "PendingSecondFactor"("opaqueTokenHash");

-- CreateIndex
CREATE INDEX "PendingSecondFactor_expiresAt_idx" ON "PendingSecondFactor"("expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "UserPreference_accountId_key_key" ON "UserPreference"("accountId", "key");

-- CreateIndex
CREATE INDEX "LocalResourceState_accountId_resource_stateKey_idx" ON "LocalResourceState"("accountId", "resource", "stateKey");

-- CreateIndex
CREATE UNIQUE INDEX "LocalResourceState_accountId_resource_resourceId_stateKey_key" ON "LocalResourceState"("accountId", "resource", "resourceId", "stateKey");

-- CreateIndex
CREATE INDEX "ResourceCache_expiresAt_idx" ON "ResourceCache"("expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "ResourceCache_accountId_cacheKey_key" ON "ResourceCache"("accountId", "cacheKey");

-- CreateIndex
CREATE INDEX "AuditEvent_accountId_createdAt_idx" ON "AuditEvent"("accountId", "createdAt");

-- AddForeignKey
ALTER TABLE "ApiToken" ADD CONSTRAINT "ApiToken_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "UserAccount"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PendingSecondFactor" ADD CONSTRAINT "PendingSecondFactor_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "UserAccount"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UserPreference" ADD CONSTRAINT "UserPreference_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "UserAccount"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LocalResourceState" ADD CONSTRAINT "LocalResourceState_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "UserAccount"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ResourceCache" ADD CONSTRAINT "ResourceCache_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "UserAccount"("id") ON DELETE CASCADE ON UPDATE CASCADE;
