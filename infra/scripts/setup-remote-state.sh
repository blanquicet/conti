#!/bin/bash
# =============================================================================
# Setup Terraform Remote State en Azure Storage
# =============================================================================
# Este script crea el Storage Account y Container para almacenar el estado
# de Terraform de forma remota. Esto permite:
# - Compartir estado entre múltiples desarrolladores
# - GitHub Actions puede acceder al estado
# - Backup automático del estado
#
# Prerrequisitos:
#   - Azure CLI instalado y autenticado (az login)
# =============================================================================

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Setup Terraform Remote State ===${NC}"
echo ""

# Variables
SUBSCRIPTION_ID="0f6b14e8-ade9-4dc5-9ef9-d0bcbaf5f0d8"
TENANT_ID="9de9ca20-a74e-40c6-9df8-61b9e313a5b3"
RESOURCE_GROUP="gastos-rg"
LOCATION="westus2"  # Mismo que el RG
STORAGE_ACCOUNT="gastostfstate"
CONTAINER_NAME="tfstate"
STATE_KEY="gastos.tfstate"

# Verificar Azure CLI
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI no está instalado${NC}"
    exit 1
fi

# Verificar login en Azure
echo "Verificando autenticación en Azure..."
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}No estás autenticado en Azure. Iniciando login...${NC}"
    az login --tenant "$TENANT_ID"
fi

# Establecer suscripción
az account set --subscription "$SUBSCRIPTION_ID"
echo -e "${GREEN}✓ Suscripción: $(az account show --query name -o tsv)${NC}"

# Verificar si el Storage Account ya existe
echo ""
echo "Verificando si el Storage Account ya existe..."
EXISTING_SA=$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query name -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_SA" ]; then
    echo -e "${YELLOW}⚠ El Storage Account '$STORAGE_ACCOUNT' ya existe${NC}"
    echo "Verificando container..."
else
    # Crear Storage Account
    echo "Creando Storage Account '$STORAGE_ACCOUNT'..."
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --encryption-services blob \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --tags project=conti environment=production managed_by=script

    echo -e "${GREEN}✓ Storage Account creado${NC}"
fi

# Obtener la clave del Storage Account
echo ""
echo "Obteniendo clave de acceso..."
STORAGE_KEY=$(az storage account keys list \
    --resource-group "$RESOURCE_GROUP" \
    --account-name "$STORAGE_ACCOUNT" \
    --query '[0].value' -o tsv)

# Verificar si el Container ya existe
EXISTING_CONTAINER=$(az storage container show \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$STORAGE_KEY" \
    --query name -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_CONTAINER" ]; then
    echo -e "${YELLOW}⚠ El container '$CONTAINER_NAME' ya existe${NC}"
else
    # Crear Container
    echo "Creando container '$CONTAINER_NAME'..."
    az storage container create \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY"

    echo -e "${GREEN}✓ Container creado${NC}"
fi

# Mostrar configuración
echo ""
echo "=============================================="
echo -e "${GREEN}✅ Terraform Remote State configurado${NC}"
echo "=============================================="
echo ""
echo "Añade esto a tu main.tf (ya debería estar descomentado):"
echo ""
echo -e "${YELLOW}terraform {
  backend \"azurerm\" {
    resource_group_name  = \"$RESOURCE_GROUP\"
    storage_account_name = \"$STORAGE_ACCOUNT\"
    container_name       = \"$CONTAINER_NAME\"
    key                  = \"$STATE_KEY\"
  }
}${NC}"
echo ""
echo "=============================================="

# Verificar si hay estado local para migrar
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$INFRA_DIR/terraform.tfstate" ]; then
    echo ""
    echo -e "${YELLOW}Se detectó un terraform.tfstate local.${NC}"
    read -p "¿Quieres migrar el estado al backend remoto? (y/N): " MIGRATE

    if [[ "$MIGRATE" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Para migrar el estado, ejecuta:"
        echo "  cd $INFRA_DIR"
        echo "  terraform init -migrate-state"
        echo ""
        echo "Terraform te preguntará si quieres copiar el estado al nuevo backend."
    fi
fi

echo ""
echo -e "${GREEN}=== Setup completado ===${NC}"
