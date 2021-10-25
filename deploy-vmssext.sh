#!/bin/bash

# Script executed by user or ExpressV2 extension to deploy VMSS startup script.
# Responsible for:
#   - update the post setup script to connect between the vmss and AKS
#   - install the vmss setup script as a custom extension
#   - secrets are not retrieved by this script (anymore). They are downloaded by the azure key vault instead
#   - supplies details to the custom extension script to post-process certificates downloaded by the AKV extension

# Stop on error.
set -e
CurrentDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
currentScriptName=`basename "$0"`

echo "CurrentDir: $CurrentDir"
echo "currentScriptName: $currentScriptName"

ENV="test"
LOCATION="eastus"
BASEHOSTNAME="irms.azure.com"
AKSHOSTNAME="irms-zhaoyufu.onebox.clouddatahub-int.net"
AKSPORT=443


DomainName="${BASEHOSTNAME}"
AksDomainName="${AKSHOSTNAME}"
AksPort="${AKSPORT}"
certificateStoreLocation="/scripts/certs/client.cer"


# Create directory under /tmp
DeploymentDir="./tempdeploymentdir"
mkdir -p $DeploymentDir
echo "** Update PostSetup file"
postSetup="./vmss-post-setup.sh"
postSetupScript="$DeploymentDir/PostSetup"
cat $postSetup |  \
sed "s|\[\[DomainName\]\]|$DomainName|g" | \
sed "s|\[\[AksDomainName\]\]|$AksDomainName|g" | \
sed "s|\[\[AksPort\]\]|$AksPort|g" | \
sed 's|\$|\\\$|g' > "$postSetupScript"


echo "** Update VmssSetup file"
vmssSetupScript="$DeploymentDir/VmssSetup"
cat "./vmss-setup.sh" | \
sed -e "/#SETUP/r $postSetupScript" | \
sed -e "s|\[\[CLIENT_CERTIFICATE\]\]|${clientCertSecretName}|g" > "$vmssSetupScript"

echo "** running  VmssSetup file"
sudo  bash $vmssSetupScript

echo "** running  PostSetup file"
sudo  bash $postSetupScript

echo "** Finish install vmss extension"
