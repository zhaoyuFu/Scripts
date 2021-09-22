#!/bin/bash

# Script used to setup VMSS
# Stop on error.
set -e

function process_openresty_certificate()
{
    local certificatePath=$1
    local keyFile=$2
    local certFile=$3

    echo "Install certificate from $certificatePath"
    if [ ! -f "$certificatePath" ]; then
        echo "Certificate $certificatePath does not exist"
        return 1
    fi

    openssl pkey -in $certificatePath -out ${keyFile}
    openssl crl2pkcs7 -nocrl -certfile $certificatePath | openssl pkcs7 -print_certs -out ${certFile}

    # Monitor changes to certificate file using incron
    echo "Monitor certificate with incron job file $incronFile"
    echo "$certificatePath IN_CLOSE_WRITE,IN_ATTRIB,IN_DONT_FOLLOW /usr/local/bin/reloadCertificate.sh $certificatePath $keyFile $certFile $%" >> $incronFile
    incrontab -u root $incronFile
}

#-------------------------------------------------------------------------------
# Generate certificate refresh script
reloadCertificateScript="/usr/local/bin/reloadCertificate.sh"

echo '#!/bin/bash
set -e
readonly LOG_FILE="/var/log/incron-purview.log"
touch $LOG_FILE
exec 1>>$LOG_FILE
exec 2>&1
date
echo "Update certificate from $1"
echo "Key file: $2"
echo "Certificate file: $3"
echo "Monitoring event: $4"
if [ $4 == "IN_IGNORED" ]; then
    echo "Ignoring $4 event"
    exit 0
fi
echo "Thumbprint: $(openssl x509 -in $1 -fingerprint -noout)"
openssl pkey -in $1 -out $2
openssl crl2pkcs7 -nocrl -certfile $1 | openssl pkcs7 -print_certs -out $3
echo "Reloading openresty configuration"
service openresty reload
echo "done!"' > $reloadCertificateScript
chmod +x $reloadCertificateScript

# create an empty incron list of jobs
incronFile="/usr/local/bin/incron.txt"
> $incronFile

#-------------------------------------------------------------------------------
# Install server/client certificates for Nginx/Openresty
if ! process_openresty_certificate [[SERVER_CERTIFICATE]] /etc/openresty/tls.key /etc/openresty/tls.cer; then
    exit 1
fi
if ! process_openresty_certificate [[CLIENT_CERTIFICATE]] /etc/openresty/client.key /etc/openresty/client.cer; then
    exit 1
fi

#-------------------------------------------------------------------------------
echo "Configure mdsd"

# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/instance-metadata-service
imdsURL="http://169.254.169.254/metadata/instance/compute/location?api-version=2017-04-02&format=text"
export MDSD_REGION="$(curl -H Metadata:True --silent $imdsURL)"
if [ ! "$MDSD_REGION" ]; then
    echo "Can't get region from metadata service"
    exit 1
fi

cp /etc/default/mdsd.template /etc/default/mdsd
sed -i "s|\[\[MDSD_AUTH_ID\]\]|[[MDSD_AUTH_ID]]|g" /etc/default/mdsd && \
sed -i "s|\[\[MDSD_AKV_CERTIFICATE_STORE_PATH\]\]|[[MDSD_AKV_CERTIFICATE_STORE_PATH]]|g" /etc/default/mdsd && \
sed -i "s|\[\[MDSD_ENVIRONMENT\]\]|[[MDSD_ENVIRONMENT]]|g" /etc/default/mdsd && \
sed -i "s|\[\[MDSD_ACCOUNT\]\]|[[MDSD_ACCOUNT]]|g" /etc/default/mdsd && \
sed -i "s|\[\[MDSD_NAMESPACE\]\]|[[MDSD_NAMESPACE]]|g" /etc/default/mdsd && \
sed -i "s|\[\[MDSD_TENANT\]\]|[[MDSD_TENANT]]|g" /etc/default/mdsd && \
sed -i "s|\[\[MDSD_ROLE\]\]|[[MDSD_ROLE]]|g" /etc/default/mdsd && \
sed -i "s|\[\[MDSD_REGION\]\]|${MDSD_REGION,,}|g" /etc/default/mdsd || exit 1

sed -i "s|export MONITORING_CONFIG_VERSION=.*|export MONITORING_CONFIG_VERSION=[[MDSD_VERSION]]|g" /etc/default/mdsd

echo "Restart services"
service mdsd restart
service azsecd restart

echo "Manually create heartbeat"
azsecd manual -s heartbeat

echo "Dump error log"
tail /var/log/mdsd.err

echo "Enable service tunnel"
service servicetunnel restart
service servicetunnel status

echo "Enable firewall for https"
ufw allow https/tcp

echo "Generate post setup script"
postSetupScript="/usr/bin/postSetup.sh"
cat <<EOF > $postSetupScript #SETUP
EOF

echo "Launch post setup script"
chmod 755 $postSetupScript
$postSetupScript infra

echo "** Restart fluentd"
service td-agent restart
service td-agent status

echo "Done..."
