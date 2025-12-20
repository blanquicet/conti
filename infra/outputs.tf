# =============================================================================
# Outputs
# =============================================================================

output "postgres_server_fqdn" {
  description = "Fully qualified domain name of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.auth.fqdn
}

output "postgres_server_name" {
  description = "Name of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.auth.name
}

output "postgres_database_name" {
  description = "Name of the authentication database"
  value       = azurerm_postgresql_flexible_server_database.auth.name
}

output "postgres_admin_username" {
  description = "Administrator username"
  value       = azurerm_postgresql_flexible_server.auth.administrator_login
}

output "postgres_admin_password" {
  description = "Administrator password (sensitive)"
  value       = random_password.postgres_admin.result
  sensitive   = true
}

# Connection string for the Go backend (DATABASE_URL format)
output "database_url" {
  description = "PostgreSQL connection string for the backend (sensitive)"
  value       = "postgres://${azurerm_postgresql_flexible_server.auth.administrator_login}:${urlencode(random_password.postgres_admin.result)}@${azurerm_postgresql_flexible_server.auth.fqdn}:5432/${azurerm_postgresql_flexible_server_database.auth.name}?sslmode=require"
  sensitive   = true
}

# Instructions output
output "next_steps" {
  description = "Instructions after applying"
  value       = <<-EOT

    ✅ PostgreSQL server created successfully!

    To get the connection string (DATABASE_URL):
      terraform output -raw database_url

    To connect with psql:
      psql "$(terraform output -raw database_url)"

    To run migrations:
      export DATABASE_URL="$(terraform output -raw database_url)"
      cd ../backend
      migrate -path migrations -database "$DATABASE_URL" up

  EOT
}
