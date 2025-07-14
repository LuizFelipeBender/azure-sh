az group create --name lugo --location brazilsouth

az vm create  --resource-group lugo --name base-vm-no-trustedlaunch --image Ubuntu2204 --size Standard_DS2_v2 --admin-username azureuser --generate-ssh-keys --security-type Standard

# Vincular o owner na VM

# Posteriormente execução do install-ama.sh

az vm deallocate   --resource-group lugo --name base-vm-no-trustedlaunch

az vm generalize --resource-group lugo   --name base-vm-no-trustedlaunch

az vm create --resource-group lugo --name nova-vm-customizada --image image-base-vm-no-trustedlaunch --admin-username azureuser --generate-ssh-keys --size Standard_DS2_v2

az image create --resource-group MEURG --name image-base-vm-no-trustedlaunch --source base-vm-no-trustedlaunch --os-type Linux --hyper-v-generation V2
sudo systemctl status azuremonitoragent
sudo waagent -deprovision+user 