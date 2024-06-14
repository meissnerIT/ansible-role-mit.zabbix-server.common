#!/bin/sh
#
# Distributed via ansible - mit.zabbix-server.common
#
# v2024-05-14

# FreeBSD needs PATH set
export PATH=/bin:/usr/bin:/usr/local/bin

curl -sS --head $1|grep "$2: "|awk '{print $2;}'

