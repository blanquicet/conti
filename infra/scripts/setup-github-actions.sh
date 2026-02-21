#!/bin/bash
# =============================================================================
# Setup GitHub Actions para Terraform
# =============================================================================
# Este script crea el Service Principal y configura los secrets en GitHub.
# Ejecutar una sola vez para configurar CI/CD.
#
# Prerrequisitos:
#   - Azure CLI instalado y autenticado (az login)
#   - GitHub CLI instalado y autenticado (gh auth login) [opcional]
# =============================================================================

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Setup GitHub Actions para Conti ===${NC}"
echo ""

# Variables
SUBSCRIPTION_ID="0f6b14e8-ade9-4dc5-9ef9-d0bcbaf5f0d8"
TENANT_ID="9de9ca20-a74e-40c6-9df8-61b9e313a5b3"
SP_NAME="github-actions-gastos"
GITHUB_REPO="blanquicet/conti"  # Repositorio de GitHub

# Verificar Azure CLI
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI no está instalado${NC}"
    echo "Instalar: https://docs.microsoft.com/cli/azure/install-azure-cli"
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

# Verificar si el SP ya existe
echo ""
echo "Verificando si el Service Principal ya existe..."
EXISTING_SP=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_SP" ]; then
    echo -e "${YELLOW}⚠ El Service Principal '$SP_NAME' ya existe (appId: $EXISTING_SP)${NC}"
    read -p "¿Quieres recrearlo? (y/N): " RECREATE
    if [[ "$RECREATE" =~ ^[Yy]$ ]]; then
        echo "Eliminando SP existente..."
        az ad sp delete --id "$EXISTING_SP"
        EXISTING_SP=""
    else
        echo "Usando SP existente. Necesitarás resetear las credenciales manualmente si no las tienes."
        exit 0
    fi
fi

# Crear Service Principal
echo ""
echo "Creando Service Principal '$SP_NAME'..."
SP_OUTPUT=$(az ad sp create-for-rbac \
    --name "$SP_NAME" \
    --role Contributor \
    --scopes "/subscriptions/$SUBSCRIPTION_ID" \
    --query "{clientId:appId, clientSecret:password, tenantId:tenant}" \
    -o json)

CLIENT_ID=$(echo "$SP_OUTPUT" | jq -r '.clientId')
CLIENT_SECRET=$(echo "$SP_OUTPUT" | jq -r '.clientSecret')

echo -e "${GREEN}✓ Service Principal creado${NC}"

# Asignar User Access Administrator (necesario para crear role assignments RBAC,
# por ejemplo: asignar "Cognitive Services OpenAI User" a la Managed Identity)
echo ""
echo "Asignando rol 'User Access Administrator' al Service Principal..."
az role assignment create \
    --assignee "$CLIENT_ID" \
    --role "User Access Administrator" \
    --scope "/subscriptions/$SUBSCRIPTION_ID" \
    -o none

echo -e "${GREEN}✓ Rol 'User Access Administrator' asignado${NC}"
echo ""

# Mostrar valores
echo "=============================================="
echo -e "${YELLOW}GUARDA ESTOS VALORES - Solo se muestran una vez${NC}"
echo "=============================================="
echo ""
echo "ARM_CLIENT_ID=$CLIENT_ID"
echo "ARM_CLIENT_SECRET=$CLIENT_SECRET"
echo "ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
echo "ARM_TENANT_ID=$TENANT_ID"
echo ""
echo "=============================================="

# Intentar configurar GitHub secrets automáticamente
if command -v gh &> /dev/null; then
    echo ""
    echo "GitHub CLI detectado. ¿Configurar secrets automáticamente?"
    read -p "Repositorio [$GITHUB_REPO]: " INPUT_REPO
    GITHUB_REPO="${INPUT_REPO:-$GITHUB_REPO}"
    
    read -p "¿Configurar secrets en $GITHUB_REPO? (y/N): " CONFIGURE_GH
    if [[ "$CONFIGURE_GH" =~ ^[Yy]$ ]]; then
        echo "Configurando secrets en GitHub..."
        
        gh secret set ARM_CLIENT_ID --repo "$GITHUB_REPO" --body "$CLIENT_ID"
        gh secret set ARM_CLIENT_SECRET --repo "$GITHUB_REPO" --body "$CLIENT_SECRET"
        gh secret set ARM_SUBSCRIPTION_ID --repo "$GITHUB_REPO" --body "$SUBSCRIPTION_ID"
        gh secret set ARM_TENANT_ID --repo "$GITHUB_REPO" --body "$TENANT_ID"
        
        echo -e "${GREEN}✓ Secrets configurados en GitHub${NC}"
    fi
else
    echo ""
    echo -e "${YELLOW}Para configurar manualmente en GitHub:${NC}"
    echo "1. Ve a: https://github.com/$GITHUB_REPO/settings/secrets/actions"
    echo "2. Añade estos secrets:"
    echo "   - ARM_CLIENT_ID"
    echo "   - ARM_CLIENT_SECRET"
    echo "   - ARM_SUBSCRIPTION_ID"
    echo "   - ARM_TENANT_ID"
fi

echo ""
echo -e "${GREEN}=== Setup completado ===${NC}"
