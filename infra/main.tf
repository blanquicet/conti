# =============================================================================
# Gastos App - Infrastructure (Terraform)
# =============================================================================
# This configuration manages Azure resources for the Gastos app.
# Phase 1: PostgreSQL for authentication only.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state - stored in Azure Storage
  backend "azurerm" {
    resource_group_name  = "gastos-rg"
    storage_account_name = "gastostfstate"
    container_name       = "tfstate"
    key                  = "gastos.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# =============================================================================
# Data Sources - Reference existing resources (not managed by Terraform)
# =============================================================================

data "azurerm_resource_group" "gastos" {
  name = var.resource_group_name
}

# =============================================================================
# Random password for PostgreSQL admin
# =============================================================================

resource "random_password" "postgres_admin" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# =============================================================================
# PostgreSQL Flexible Server (for authentication data)
# =============================================================================

resource "azurerm_postgresql_flexible_server" "auth" {
  name                = var.postgres_server_name
  resource_group_name = data.azurerm_resource_group.gastos.name
  location            = var.postgres_location # Different from RG due to quota restrictions

  # Credentials
  administrator_login    = var.postgres_admin_username
  administrator_password = random_password.postgres_admin.result

  # SKU - Burstable B1ms (cost-effective for auth workload)
  sku_name = "B_Standard_B1ms"

  # Storage
  storage_mb = 32768 # 32 GB minimum

  # Version
  version = "16"

  # Backup
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  # Network - Public access (with firewall rules)
  # For production, consider private endpoint
  public_network_access_enabled = true

  # Zone (no HA for burstable tier)
  zone = "1"

  tags = var.tags
}

# =============================================================================
# PostgreSQL Database
# =============================================================================

resource "azurerm_postgresql_flexible_server_database" "auth" {
  name      = var.postgres_database_name
  server_id = azurerm_postgresql_flexible_server.auth.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# =============================================================================
# Firewall Rules
# =============================================================================

# Allow Azure services (needed for Azure Container Apps, Functions, etc.)
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.auth.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Allow your current IP for local development (optional, update as needed)
resource "azurerm_postgresql_flexible_server_firewall_rule" "dev_ip" {
  count            = var.dev_ip_address != "" ? 1 : 0
  name             = "AllowDevIP"
  server_id        = azurerm_postgresql_flexible_server.auth.id
  start_ip_address = var.dev_ip_address
  end_ip_address   = var.dev_ip_address
}

# =============================================================================
# PostgreSQL Configuration (security hardening)
# =============================================================================

resource "azurerm_postgresql_flexible_server_configuration" "require_ssl" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.auth.id
  value     = "ON"
}

resource "azurerm_postgresql_flexible_server_configuration" "log_connections" {
  name      = "log_connections"
  server_id = azurerm_postgresql_flexible_server.auth.id
  value     = "ON"
}
