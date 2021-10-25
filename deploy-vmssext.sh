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


if [[ -z $ENV ]];then
    echo "ENV is empty. Please set a valid value for environment." && exit 1
fi

if [[ -z $LOCATION ]];then
    echo "LOCATION is empty. Please set a valid value for the location." && exit 1
fi

if [[ -z $BASEHOSTNAME ]];then
    echo "BASEHOSTNAME is empty. Please set a valid value for the base host name that the proxy cluster will accept requests for." && exit 1
fi

if [[ -z $AKSHOSTNAME ]];then
    echo "AKSHOSTNAME is empty. Please set a valid value for the host name of the AKS cluster where requests are forwarded to." && exit 1
fi

if [[ -z $AKSPORT ]];then
    AKSPORT=443
    echo "AKSPORT is empty. The AKS SSL port will default to $AKSPORT"
fi


DomainName="${BASEHOSTNAME}"
AksDomainName="${AKSHOSTNAME}"
AksPort="${AKSPORT}"
gcsTenantLocation="${LOCATION}"
gcsEnvironment="${GCS_ENVIRONMENT}"
gcsNamespace="${GCS_NAMESPACE}"
gcsVersion="${GCS_VERSION}"
gcsAccount="${GCS_ACCOUNT}"
certificateStoreLocation="/var/lib/waagent/Microsoft.Azure.KeyVault.Store"


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
sed -e "s|\[\[SERVER_CERTIFICATE\]\]|${certificateStoreLocation}/${keyVaultName}.${serviceCertSecretName}|g" | \
sed -e "s|\[\[CLIENT_CERTIFICATE\]\]|${certificateStoreLocation}/${keyVaultName}.${clientCertSecretName}|g" > "$vmssSetupScript"

echo "** running  VmssSetup file"
sudo  bash $vmssSetupScript

echo "** running  PostSetup file"
sudo  bash $postSetupScript

echo "** Finish install vmss extension"
