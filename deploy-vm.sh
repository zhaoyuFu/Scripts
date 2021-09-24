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

#login
echo "az login --identity"
az login --identity > azLoginResult.txt
exit_code=$?
if [ $exit_code -ne 0 ]; then
    echo "az login failed."
    exit $exit_code
fi


AzureResourceGroupName="zhaoyuWorkbench"
SubscriptionId="b371d9e7-d3c2-4b1a-83ec-84e1f50c2222"
GCS_ENVIRONMENT="test"
GCS_NAMESPACE="zhaoyufu"
GCS_VERSION= "1.0"
GCS_ACCOUNT="zhaoyuAccount"

# Set current subscription. SubscriptionId and AzureResourceGroupName are passed as implicit arguments by Ev2
# https://ev2docs.azure.net/features/extensibility/shell/artifacts.html#rollout-parameters
echo "az account set -s $SubscriptionId"
az account set -s "$SubscriptionId"
exit_code=$?
if [ $exit_code -ne 0 ]; then
    echo "az account set failed."
    exit $exit_code
fi

# VmssResourceGroupName=""
# VmssResourceName="purviewproxy-${ENV}-vmss-${LOCATION}"
DomainName="${BASEHOSTNAME}"
AksDomainName="${AKSHOSTNAME}"
AksPort="${AKSPORT}"
gcsTenantLocation="${LOCATION}"
gcsEnvironment="${GCS_ENVIRONMENT}"
gcsNamespace="${GCS_NAMESPACE}"
gcsVersion="${GCS_VERSION}"
gcsAccount="${GCS_ACCOUNT}"
certificateStoreLocation="/var/lib/waagent/Microsoft.Azure.KeyVault.Store"

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
sed -e "s|\[\[SERVER_CERTIFICATE\]\]|${certificateStoreLocation}/${keyVaultName}.${serviceCertSecretName}|g" | \
sed -e "s|\[\[CLIENT_CERTIFICATE\]\]|${certificateStoreLocation}/${keyVaultName}.${clientCertSecretName}|g" | \
sed -e "s|\[\[MDSD_AKV_CERTIFICATE_STORE_PATH\]\]|${certificateStoreLocation}|g" | \
sed -e "s|\[\[MDSD_AUTH_ID\]\]|${genevaCertSubjectName}|g" | \
sed -e "s|\[\[MDSD_ENVIRONMENT\]\]|${gcsEnvironment}|g" | \
sed -e "s|\[\[MDSD_NAMESPACE\]\]|${gcsNamespace}|g" | \
sed -e "s|\[\[MDSD_VERSION\]\]|${gcsVersion}|g" | \
sed -e "s|\[\[MDSD_ACCOUNT\]\]|${gcsAccount}|g" | \
sed -e "s|\[\[MDSD_ROLE\]\]|${VmssResourceName}|g" | \
sed -e "s|\[\[MDSD_TENANT\]\]|${gcsTenantLocation}|g" > "$vmssSetupScript"

cat $vmssSetupScript


protectedSettingsFile="$DeploymentDir/protectedSettings.json"

# cat <<EOF > $protectedSettingsFile
# {
#     "script": "$(cat $vmssSetupScript | gzip -9 | base64 -w 0)"
# }
# EOF

# extension=$(az vmss extension list --resource-group $VmssResourceGroupName --vmss-name $VmssResourceName --query "[?name=='VmssSetup'].name" -o tsv)

# if [[ -n $extension ]]; then
#    echo "** ${extension} extension found. Uninstalling it before updating"
#    az vmss extension delete \
#         --name VmssSetup \
#         --resource-group "$VmssResourceGroupName" \
#         --vmss-name "$VmssResourceName" > /dev/null
# fi

# timestamp=$(date +%s)
# echo "** Install VmssSetup extension - $timestamp"
# az vmss extension set \
#     -n "CustomScript" \
#     -g "$VmssResourceGroupName" \
#     --vmss-name "$VmssResourceName" \
#     --publisher "Microsoft.Azure.Extensions" \
#     --extension-instance-name "VmssSetup" \
#     --settings "{\"timestamp\": $timestamp}" \
#     --protected-settings "$protectedSettingsFile" > /dev/null

# echo "** Update vmss"
# az vmss update \
#     -g $VmssResourceGroupName \
#     -n $VmssResourceName > /dev/null

# rm -r $DeploymentDir

echo "** Finish install vmss extension"
