#!/bin/bash

# Post script used to finsh VMSS startup script
# Stop on error.
set -e

echo "** AKS Service DNS name: [[AksDomainName]]"
echo "** AKS Service Port: [[AksPort]]"
echo "** Update nginx.conf file"
cp /etc/openresty/nginx.conf.template /etc/openresty/nginx.conf
sed -i "s|\[\[DomainName\]\]|[[DomainName]]|g" /etc/openresty/nginx.conf

cp /etc/openresty/location.conf.template /etc/openresty/location.conf
sed -i "s|\[\[AKSServiceILB\]\]|[[AksDomainName]]|g" /etc/openresty/location.conf
sed -i "s|\[\[AKSServicePort\]\]|[[AksPort]]|g" /etc/openresty/location.conf

if [ -f "/usr/local/openresty/nginx/logs/nginx.pid" ]; then
    echo "Restart OpenResty service"
    service openresty reload
else
    echo "Start OpenResty service"
    service openresty start
fi
service openresty status

echo "** Done"
