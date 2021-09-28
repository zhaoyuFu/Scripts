#!/bin/bash

ssl_cert_kv_name="adms-test-kv"

# Downloading and split ro certificates.
function az_download_and_split_ssl_certificate()
{
    # expects the a filename like foo.pfx 
    # generates output file names like foo.cer, foo.key, foo.rsa.key and foo.ca.cer
    local pfx_file="${1}"
    local ssl_cert_secret_name=$2
    local base_name=$(basename ${pfx_file} .pfx)
    local cer_file="${base_name}.cer"
    local key_file="${base_name}.key"
    local ca_file="${base_name}.ca.cer"

    local rsa_key_file="${base_name}.rsa.key"
    local az_command="az keyvault secret download --vault-name ${ssl_cert_kv_name} --name ${ssl_cert_secret_name} --encoding base64 --file ${pfx_file}"
    exec_dry_run "${az_command}" || return $?
    echo "password text."
    local passwordplaintext=""

    exec_dry_run "openssl pkcs12 -in $pfx_file -out $cer_file -nokeys -clcerts -password pass:$passwordplaintext" || return $?
    exec_dry_run "openssl pkcs12 -in $pfx_file -out $key_file -nocerts -nodes -password pass:$passwordplaintext" || return $?
    exec_dry_run "openssl pkcs12 -in $pfx_file -out $ca_file  -cacerts -nokeys -chain -password pass:$passwordplaintext" || return $?
    exec_dry_run "openssl rsa -in $key_file -out $rsa_key_file" || return $?

    echo "Downloading the cert completed."
    # Download and append the intermediate certificate
    local certScheme="$(openssl x509 -in $cer_file -noout -text | grep "CA Issuers" | cut -d':' -f2)"
    local certHostAndPath="$(openssl x509 -in $cer_file -noout -text | grep "CA Issuers" | cut -d':' -f3)"
    local intermediateCertUri="${certScheme}:${certHostAndPath}"
    if [ ! "$intermediateCertUri" == ":" ]; then
        echo "Getting the intermediate cert from ${intermediateCertUri}"      
        (curl -s ${intermediateCertUri} | openssl x509 -inform der) >> $cer_file       
    else
        echo "No intermediate certificate uri found for certificate ${ssl_cert_secret_name}"
    fi
}

function exec_dry_run()
{   
    local command="$@"
     $command
}
