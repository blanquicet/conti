# Backend - Database Migrations

This document describes how to run database migrations for the Gastos authentication backend.

## Prerequisites

1. **golang-migrate CLI** installed:

   ```bash
   curl -L https://github.com/golang-migrate/migrate/releases/download/v4.17.0/migrate.linux-amd64.tar.gz | tar xvz
   sudo mv migrate /usr/local/bin/
   ```

2. **Terraform** configured (to get DATABASE_URL):

   ```bash
   cd infra
   terraform init
   ```

## Running Migrations

### 1. Get the DATABASE_URL

```bash
cd infra
export DATABASE_URL=$(terraform output -raw database_url)
```

The DATABASE_URL is automatically URL-encoded to handle special characters in the password.

### 2. Run migrations

```bash
cd backend
migrate -path ./migrations -database "$DATABASE_URL" up
```

### 3. Check current version

```bash
migrate -path ./migrations -database "$DATABASE_URL" version
```

## Other Commands

### Rollback last migration

```bash
migrate -path ./migrations -database "$DATABASE_URL" down 1
```

### Rollback all migrations

```bash
migrate -path ./migrations -database "$DATABASE_URL" down
```

### Force a specific version (use with caution)

If a migration fails midway and leaves the database in a "dirty" state:

```bash
# Force state back to version 0 (no migrations applied)
migrate -path ./migrations -database "$DATABASE_URL" force 0

# Or drop everything and start fresh (DESTRUCTIVE!)
migrate -path ./migrations -database "$DATABASE_URL" drop -f
migrate -path ./migrations -database "$DATABASE_URL" up
```

## Migration Files

| Migration | Description |
| --------- | ----------- |
| `001_create_users` | Creates the `users` table for authentication |
| `002_create_sessions` | Creates the `sessions` table for session-based auth |
| `003_create_password_resets` | Creates the `password_resets` table for password recovery |

## Notes

- **Azure PostgreSQL**: `gen_random_uuid()` is available natively in PostgreSQL 13+ without needing the `pgcrypto` extension.
- **SSL**: Connection requires `sslmode=require` (enforced by Azure).
- All timestamps use `TIMESTAMPTZ` for timezone-aware storage.
