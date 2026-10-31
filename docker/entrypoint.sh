#!/bin/sh
set -e

cd /app/apps/api

# Optional demo mode: DEMO=true switches the provider to the fake provider.
if [ "${DEMO:-false}" = "true" ] || [ "${DEMO:-0}" = "1" ]; then
  export EDUFLOW_PROVIDER=fake
  echo "Demo mode enabled (fake provider)."
fi

echo "Applying database migrations..."
npx prisma migrate deploy --schema prisma/schema.prisma

echo "Starting EduFlow API..."
exec node dist/main.js