#!/bin/sh
#
# Distributed via ansible - mit.zabbix-server.common
#
# check-smtp-dane.sh — check DANE TLSA record against live SMTP certificate
# Usage: check-smtp-dane.sh <hostname> <port>
# Exit codes are always 0 (Zabbix evaluates the printed value, not the exit code)
# Return values: 0=OK, 1=TLSA missing, 2=hash mismatch, 3=error (cert unreachable)

HOSTNAME="${1}"
PORT="${2}"

# Validate mandatory arguments. If hostname or port is missing or empty,
# return error code 3 immediately.
if [ -z "$HOSTNAME" ] || [ -z "$PORT" ]; then
    echo "99"
    exit 0
fi

# 1. Retrieve the live certificate via STARTTLS and compute the SHA-256 hash
#    of its public key (SPKI). This mirrors TLSA usage 3, selector 1, matching type 1.
live_hash=$(echo | openssl s_client -starttls smtp -connect "${HOSTNAME}:${PORT}" 2>/dev/null \
    | openssl x509 -noout -pubkey 2>/dev/null \
    | openssl pkey -pubin -outform DER 2>/dev/null \
    | openssl sha256 2>/dev/null \
    | awk '{ print tolower($2); }')

# If no hash could be computed the certificate is unreachable (server down,
# TLS handshake failed, etc.). Return error code 3.
if [ -z "$live_hash" ]; then
    echo "3"
    exit 0
fi

# 2. Query the TLSA record from DNS with DNSSEC validation (+dnssec flag).
#    Filter for DANE-EE records (usage 3, selector 1, matching type 1) and
#    extract the hash field (4th column). Take the first matching record.
tlsa_record=$(dig +dnssec TLSA "_${PORT}._tcp.${HOSTNAME}" +short 2>/dev/null \
    | awk '/^3 1 1/ { print tolower($4$5); }' \
    | head -1)

# If no TLSA record is found the DANE configuration is missing or broken.
# Return code 1 so Zabbix can alert.
if [ -z "$tlsa_record" ]; then
    echo "2"
    exit 0
fi

# 3. Compare the live certificate hash with the TLSA record hash.
#    A mismatch means the private key has changed but the TLSA record
#    was not updated — DANE validation will fail for remote servers.
if [ "$live_hash" = "$tlsa_record" ]; then
    echo "1"
else
    echo "0"
fi
