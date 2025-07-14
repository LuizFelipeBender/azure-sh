#!/bin/bash

# === Variáveis ===
VM_NAME="base-vm-no-trustedlaunch"
RG_NAME="MEURG"              # Resource Group da VM
DCR_NAME="DCR"
DCR_RG_NAME="laboratorio"    # Resource Group da DCR
ASSOCIATION_NAME="ama-association"
SUBSCRIPTION="83ebaf50-9081-4df9-972e-75ef73901fe0"

# === Funções auxiliares ===
log_info() { echo -e "\U0001f527 $1"; }
log_step() { echo -e "\U0001f50d $1"; }
log_success() { echo -e "\u2705 $1"; }
log_error() { echo -e "\u274c $1"; }

# === Início ===
log_info "[AMA] Iniciando instalação do Azure Monitor Agent na VM '$VM_NAME'..."

# Verifica se Azure CLI está instalada, senão instala
if ! command -v az &> /dev/null; then
    log_step "[AMA] Azure CLI não encontrada. Iniciando instalação..."
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    if [ $? -eq 0 ]; then
        log_success "[AMA] Azure CLI instalada com sucesso."
    else
        log_error "[AMA] Falha na instalação da Azure CLI."
        exit 1
    fi
else
    log_success "[AMA] Azure CLI encontrada."
fi

# Login com Managed Identity
log_step "[AMA] Fazendo login com Managed Identity..."
if az login --identity &> /dev/null; then
    log_success "[AMA] Login com Managed Identity realizado."
else
    log_error "[AMA] Falha ao realizar login com Managed Identity."
    exit 1
fi

# Permitir uso de extensões preview
log_step "[AMA] Habilitando extensões preview na Azure CLI..."
az config set extension.use_dynamic_install=yes_without_prompt
az config set extension.dynamic_install_allow_preview=true

# Remove extensões anteriores com falha, se existirem
log_step "[AMA] Limpando extensões antigas ou incorretas..."
az vm extension delete --name AzureMonitorWindowsAgent --resource-group "$RG_NAME" --vm-name "$VM_NAME" --only-show-errors &> /dev/null
az vm extension delete --name AzureMonitorLinuxAgent --resource-group "$RG_NAME" --vm-name "$VM_NAME" --only-show-errors &> /dev/null

# Instala extensão correta
log_step "[AMA] Instalando Azure Monitor Agent via extensão na VM..."
az vm extension set \
  --name AzureMonitorLinuxAgent \
  --publisher Microsoft.Azure.Monitor \
  --resource-group "$RG_NAME" \
  --vm-name "$VM_NAME" \
  --enable-auto-upgrade true \
  --no-wait

log_success "[AMA] Extensão enviada para instalação."

# Aguarda alguns segundos para garantir instalação
log_step "[AMA] Aguardando 90 segundos para propagação da extensão e provisionamento..."
sleep 90

# Obtem ID da DCR
log_step "[AMA] Recuperando ID do Data Collection Rule '$DCR_NAME'..."
DCR_ID=$(az monitor data-collection rule show \
    --name "$DCR_NAME" \
    --resource-group "$DCR_RG_NAME" \
    --query id \
    -o tsv)

if [ -z "$DCR_ID" ]; then
    log_error "[AMA] Falha ao obter o ID da DCR. Verifique se o recurso existe."
    exit 1
else
    log_success "[AMA] DCR localizada: $DCR_ID"
fi

# Monta o ID da VM
VM_ID="/subscriptions/$SUBSCRIPTION/resourceGroups/$RG_NAME/providers/Microsoft.Compute/virtualMachines/$VM_NAME"

# Cria associação entre VM e DCR
log_step "[AMA] Associando DCR à VM..."
output=$(az monitor data-collection rule association create \
  --name "$ASSOCIATION_NAME" \
  --rule-id "$DCR_ID" \
  --resource "$VM_ID" \
  --description "Associação DCR para AMA via script" 2>&1)

if [ $? -eq 0 ]; then
    log_success "[AMA] DCR associada com sucesso à VM! 🎉"
else
    log_error "[AMA] Falha ao associar DCR à VM."
    echo "Detalhes do erro:"
    echo "$output"
    exit 1
fi

# Verificando status dos serviços
log_step "[AMA] Verificando status dos serviços..."

echo -e "\n--- [systemctl status azuremonitoragent] ---"
sudo systemctl status azuremonitoragent || echo "⚠️ Serviço azuremonitoragent não encontrado."

echo -e "\n--- [ps aux | grep azuremonitoragent] ---"
ps aux | grep azuremonitoragent | grep -v grep || echo "⚠️ Processo azuremonitoragent não está em execução."

echo -e "\n--- [systemctl status ama-dcr.service] ---"
sudo systemctl status ama-dcr.service || echo "⚠️ Serviço ama-dcr.service não encontrado."

log_success "[AMA] Script concluído."
