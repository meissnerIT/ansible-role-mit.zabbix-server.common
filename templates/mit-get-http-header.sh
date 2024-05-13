#!/usr/bin/env sh
#
# Distributed via ansible - mit.zabbix-server.common
#
# v2016-08-16

curl -sS --head $1|grep "$2: "|awk '{print $2;}'

