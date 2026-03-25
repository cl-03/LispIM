#!/bin/bash
# Start LispIM Backend

cd "$(dirname "$0")"

# PostgreSQL: postgresql://user:pass@host:port/db
# Default PostgreSQL user is usually 'postgres' with no password on local install
export DATABASE_URL="${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/lispim}"
export REDIS_URL="${REDIS_URL:-redis://localhost:6379/0}"

exec sbcl --load lispim-core/lispim-core.asd \
  --eval "(ql:quickload :lispim-core)" \
  --eval "(lispim-core::init-storage \"$DATABASE_URL\" \"$REDIS_URL\")" \
  --eval "(lispim-core::start-gateway :port 3000)" \
  --eval "(loop (sleep 60))"
