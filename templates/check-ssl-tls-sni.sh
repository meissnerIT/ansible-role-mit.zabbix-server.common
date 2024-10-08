#!{{ bash_bin }}
#
# Distributed via ansible - mit.zabbix-server.common
#
# script: ssltls.check 
# version: 1.3
# author: Andre Schild <a.schild aarboard.ch>
# author: Simon Kowallik <sk simonkowallik.com>
# description: 
# license: GPL2
#
# DETAIL:
# This script uses openssl s_client to check the availability of SSL or TLS services.
# Additionally it is possible to query different attributes of the x509 certificate of the queried SSL/TLS service.
# All native SSL encapsulated services should work, basically all SSL versions suppored by OpenSSL should work.
# As OpenSSL s_client also supports STARTTLS, ssltls.check supports it too. This means smtp pop3 imap ftp xmpp should
# work with STARTTLS.
#
# This script is intended for use with Zabbix 2.0
#
# REQUIRES:
#  - bash
#  - openssl
#  - coreutils
#
#
# USAGE:
#  * Shell:              ARG1      ARG2     ARG3   ARG4
#   > # ssltls-sni.check HOST:PORT SNI-NAME METHOD CHECK_TYPE
#
# ARG1: HOST:PORT
#       HOST is either a Hostname or an IP Address.
#       PORT is the TCP Port of the Service which should be checked.
#
# ARG2: METHOD
#       METHOD either the Service which should be used for STARTTLS (i.e. smtp, pop3, imap)
#       or "native" for SSL/TLS encapsulated Services like HTTPS or IMAPS.
#
# ARG3: CHECK_TYPE
#       CHECK_TYPE specifies what attribute should be checked and what will be returned.
#
#
# This is the list of supported CHECK_TYPES:
# 
#   * SSL/TLS Availability Check
#         CHECK_TYPE: simple
#         Return type: boolean
#         1: for Service is running 
#         0: for Service is down
#
#   * Certificate Attribute Checks                                                                                                                                          
#       * CHECK_TYPE: lifetime                                                                                                                                                  
#         Return type:int                                                                                                                                                       
#         Desc: Returns certificate lifetime in seconds from NOW                                                                                                                
#
#       * CHECK_TYPE: startdate
#	  Desc: Returns certificate start date, example: Feb 22 10:22:35 2012 GMT
#         Return type:text
#
#       * CHECK_TYPE: enddate
# 	  Desc: Returns certificate end date, example: Feb 23 15:31:40 2013 GMT
#         Return type:text
#
#       * CHECK_TYPE: serial
#	  Desc: Returns certificate Serial Number, example: C058924
#         Return type:hex
#
#       * CHECK_TYPE: fingerprint
#	  Desc: Returns certificate cryptographic fingerprint, example: DF:0C:6E:D0...2B:69
#	  Fingerprints can be SHA1, MD5 and other Cryptographic Hash Functions,
#	  therefore the length of the returned value can differ.
#         Return type:text
#
#       * CHECK_TYPE: subject
#	  Desc: Returns the Subject Name of the certificate.
#         Return type:text
#
#       * CHECK_TYPE: issuer
#	  Desc: Returns the Issuer Name of the certificate.
#         Return type:text
#
#       * CHECK_TYPE: subject_hash
#	  Desc: Returns OpenSSL Certificate Hash, example: 565e8c5a
#         Return type:hex
#
#       * CHECK_TYPE: issuer_hash
#	  Desc: Returns OpenSSL Certificate Hash of Issuer Certificate, example: 38d751eb
#         Return type:hex
#
# EXAMPLES:
# Check if SSL/TLS Handshake works for SMTP Service on {HOST.IP} with smtp STARTTLS
#   Item Key: ssltls.check[{HOST.IP}:25,smtp,simple]
#   Type of Information: Numeric (unsigned)
#   Data Type: boolean
#   Use from shell: ssltls.check hostip:25 smtp simple
#
# Check if SSL/TLS Handshake works for HTTPS (HTTP over SSL/TLS) on {HOST.IP]
#   Item Key: ssltls.check[{HOST.IP}:443,native,simple]
#   Type of Information: Numeric (unsigned)
#   Data Type: boolean
#   Use from shell: ssltls.check hostip:443 native simple
#
# Query the lifetime of the Certificate on {HOST.IP}, lifetime is returned in Seconds from current date.
#   Item Key: ssltls.check[{HOST.IP}:443,native,lifetime]
#   Type of Information: Numeric (unsigned)
#   Data Type: Decimal 
#   Use from shell: ssltls.check hostip:443 native lifetime
#
# Query certificate fingerprint (SHA1, MD5, SHA256, ..) from IMAPS Service (TCP 993) on {HOST.NAME}
#   Item Key: ssltls.check[{HOST.NAME}:993,native,fingerprint]
#   Type of Information: Character
#   Use from shell: ssltls.check hostname:993 native fingerprint
#
#
# ADDITIONAL PARAMETERS:
#  Path to OpenSSL, echo and timeout(coreutils) binaries should be set, if they differ.
#  TIMEOUT specifies the connect timeout of openssl.
#


# there need to be exactly 4 arguments, if not, exit 1 (error for console)
if [ $# -ne 4 ]; then
    echo "ssltls-sni.check <ip:port> <fqn> <tls-type> <check>"
    echo "tls-type: native for HTTPS/SSL or smtp|pop3|imap|ftp|xmpp for STARTTLS"
    exit 1
fi

LOC="POSIX"
export LC_ALL=$LOC

# On FreeBSD zabbix doesn't provide PATH
PATH=/bin:/usr/bin:/usr/local/bin

# assign arguments to variables
#
HOST=$1 # IP:PORT or FQDN:PORT
SNIHOST=$2 # FQN
TLS_TYPE=$3 # native or proto (which means we use starttls)
CHECK_TYPE=$4 # simple, lifetime, .., serial, .., issuer, ..

# default parameters / path to binaries / connection timeout
# 
echo_bin="/bin/echo"
timeout_bin="/usr/bin/timeout"
OPENSSL="/usr/bin/openssl" # path to openssl binary
TIMEOUT=10 # connect timeout in seconds
OPENSSL_PROTOS="smtp pop3 imap ftp xmpp" # which protocols are suppored by openssl for STARTTLS handshakes

if date --version 2>&1 | grep -qi "date: illegal option"; then
    if which -s gdate; then
        date_bin=$(which gdate)
    else
        echo "Date doesn't support parameter '--version', please install gdate from coreutils"
        exit 1
    fi
else
    date_bin=date
fi

######
# Determine Service Type (Native vs. STARTTLS)
# check if we connect to a native SSL/TLS service or use STARTTLS
if [ "$TLS_TYPE" == "native" ]; then
  # "native" SSL/TLS service, no STARTTLS command needed
  STARTTLS=""
else
  # custom protocol supplied, check if protocol is supported and build the OpenSSL starttls command
  for PROTO in $OPENSSL_PROTOS; do
    # if supplied TLS_TYPE matches supported PROTO set STARTTLS command
    if [ "$TLS_TYPE" == "$PROTO" ]; then
      STARTTLS="-starttls $PROTO"
      break
    fi
  done
  # if STARTTLS is still empty, the supplied TLS_TYPE is not a supported PROTO, we will exit 1!
  if [ "$STARTTLS" == "" ]; then
    exit 1
  fi
fi

######
# Determine Check Type (Simple vs. Advanced Value) and perform Service Check!
RETURN=""
case $CHECK_TYPE in
  "simple")
    # what certificate attribute should we use to determine if SSL/TLS Handshake works?
    X509_OPT="-subject_hash"
    # execute command
    RETURN=$($echo_bin | $timeout_bin $TIMEOUT $OPENSSL s_client -connect $HOST -servername $SNIHOST $STARTTLS 2>/dev/null | $OPENSSL x509 -noout $X509_OPT 2>/dev/null)
    # process RETURN value
    if [ "$RETURN" == "" ]; then
    # no certificate received (no subject_hash) or other error (could not connect?) send 0 to zabbix, exit 1
      echo 0
      exit 1
    else
    # certificate received (subject_hash) send 1 to zabbix, exit 0
      echo 1
      exit 0
    fi
  ;;
  "lifetime")
    X509_OPT="-enddate"
    RETURN=$($echo_bin | $timeout_bin $TIMEOUT $OPENSSL s_client -connect $HOST -servername $SNIHOST $STARTTLS 2>/dev/null | $OPENSSL x509 -noout $X509_OPT 2>/dev/null)

    if [ "$RETURN" == "" ]; then
    # no certificate attribute or other error (could not connect?) send 0 to zabbix, exit 1
      echo "" 
      exit 1
    else
    # certificate attribute received send it to zabbix, exit 0
      EXP_DATE=$($date_bin --date="$($echo_bin $RETURN | cut -d= -f2)" +%s); \
      CUR_DATE=$($date_bin --date="`$date_bin`" +%s); \
      RETURN=$(($EXP_DATE-$CUR_DATE))
      echo $RETURN
      exit 0
    fi
  ;;
  "startdate")
    X509_OPT="-startdate"
    RETURN=$($echo_bin | $timeout_bin $TIMEOUT $OPENSSL s_client -connect $HOST -servername $SNIHOST $STARTTLS 2>/dev/null | $OPENSSL x509 -noout $X509_OPT 2>/dev/null)

    if [ "$RETURN" == "" ]; then
    # no certificate attribute or other error (could not connect?) send 0 to zabbix, exit 1
      echo ""
      exit 1
    else
    # certificate attribute received send it to zabbix, exit 0
      echo ${RETURN#notBefore=}
      exit 0
    fi
  ;;
  "enddate")
    X509_OPT="-enddate"
    RETURN=$($echo_bin | $timeout_bin $TIMEOUT $OPENSSL s_client -connect $HOST -servername $SNIHOST $STARTTLS 2>/dev/null | $OPENSSL x509 -noout $X509_OPT 2>/dev/null)

    if [ "$RETURN" == "" ]; then
    # no certificate attribute or other error (could not connect?) send 0 to zabbix, exit 1
      echo ""
      exit 1
    else
    # certificate attribute received send it to zabbix, exit 0
      echo ${RETURN#notAfter=}
      exit 0
    fi
  ;;
  "serial")
    X509_OPT="-serial"
    RETURN=$($echo_bin | $timeout_bin $TIMEOUT $OPENSSL s_client -connect $HOST -servername $SNIHOST $STARTTLS 2>/dev/null | $OPENSSL x509 -noout $X509_OPT 2>/dev/null)

    if [ "$RETURN" == "" ]; then
    # no certificate attribute or other error (could not connect?) send 0 to zabbix, exit 1
      echo ""
      exit 1
    else
    # certificate attribute received send it to zabbix, exit 0
      echo ${RETURN#serial=}
      exit 0
    fi
  ;;
  "fingerprint")
    X509_OPT="-fingerprint"
    RETURN=$($echo_bin | $timeout_bin $TIMEOUT $OPENSSL s_client -connect $HOST -servername $SNIHOST $STARTTLS 2>/dev/null | $OPENSSL x509 -noout $X509_OPT 2>/dev/null)

    if [ "$RETURN" == "" ]; then
    # no certificate attribute or other error (could not connect?) send 0 to zabbix, exit 1
      echo ""
      exit 1
    else
    # certificate attribute received send it to zabbix, exit 0
      echo ${RETURN#*Fingerprint=}
      exit 0
    fi
  ;;
  "subject")
    X509_OPT="-subject"
    RETURN=$($echo_bin | $timeout_bin $TIMEOUT $OPENSSL s_client -connect $HOST -servername $SNIHOST $STARTTLS 2>/dev/null | $OPENSSL x509 -noout $X509_OPT 2>/dev/null)

    if [ "$RETURN" == "" ]; then
    # no certificate attribute or other error (could not connect?) send 0 to zabbix, exit 1
      echo ""
      exit 1
    else
    # certificate attribute received send it to zabbix, exit 0
      echo ${RETURN#subject= }
      exit 0
    fi
  ;;
  "issuer")
    X509_OPT="-issuer"
    RETURN=$($echo_bin | $timeout_bin $TIMEOUT $OPENSSL s_client -connect $HOST -servername $SNIHOST $STARTTLS 2>/dev/null | $OPENSSL x509 -noout $X509_OPT 2>/dev/null)

    if [ "$RETURN" == "" ]; then
    # no certificate attribute or other error (could not connect?) send 0 to zabbix, exit 1
      echo ""
      exit 1
    else
    # certificate attribute received send it to zabbix, exit 0
      echo ${RETURN#issuer= }
      exit 0
    fi
  ;;
  "subject_hash")
    X509_OPT="-subject_hash"
    RETURN=$($echo_bin | $timeout_bin $TIMEOUT $OPENSSL s_client -connect $HOST -servername $SNIHOST $STARTTLS 2>/dev/null | $OPENSSL x509 -noout $X509_OPT 2>/dev/null)

    if [ "$RETURN" == "" ]; then
    # no certificate attribute or other error (could not connect?) send 0 to zabbix, exit 1
      echo ""
      exit 1
    else
    # certificate attribute received send it to zabbix, exit 0
      echo ${RETURN#subject_hash= }
      exit 0
    fi
  ;;
  "issuer_hash")
    X509_OPT="-issuer_hash"
    RETURN=$($echo_bin | $timeout_bin $TIMEOUT $OPENSSL s_client -connect $HOST -servername $SNIHOST $STARTTLS 2>/dev/null | $OPENSSL x509 -noout $X509_OPT 2>/dev/null)

    if [ "$RETURN" == "" ]; then
    # no certificate attribute or other error (could not connect?) send 0 to zabbix, exit 1
      echo ""
      exit 1
    else
    # certificate attribute received send it to zabbix, exit 0
      echo ${RETURN#issuer_hash= }
      exit 0
    fi
  ;;
  "digestmode")
    X509_OPT="-text"
    RETURN=$($echo_bin | $timeout_bin $TIMEOUT $OPENSSL s_client -connect $HOST -servername $SNIHOST $STARTTLS 2>/dev/null | $OPENSSL x509 -noout  $X509_OPT  2>/dev/null | grep "Signature Algorithm")

    if [ "$RETURN" == "" ]; then
    # no certificate attribute or other error (could not connect?) send 0 to zabbix, exit 1
      echo ""
      exit 1
    else
    # certificate attribute received send it to zabbix, exit 0
      echo ${RETURN}
      exit 0
    fi
  ;;
  "ssl3")
    X509_OPT="-text"
    RETURN=$($echo_bin | $timeout_bin $TIMEOUT $OPENSSL s_client -connect $HOST -servername $SNIHOST $STARTTLS -ssl3 2>&1 >/dev/null | grep "handshake failure")
    searchString="sslv3 alert handshake failure"
    searchString2="ssl handshake failure"
    if [ "$RETURN" == "" ]; then
    # connect OK, sslv3 active, bad
      echo "1"
      exit 0
    elif [[ $RETURN == *"$searchString"* ]]
       then
	# OK; sslv3 connect error, is disabled
	echo "0"
	exit 0
    elif [[ $RETURN == *"$searchString2"* ]]
       then
	# OK; sslv3 connect error, is disabled
	echo "0"
	exit 0
    else
    # certificate attribute received send it to zabbix, exit 0
      echo $RETURN
      exit 1
    fi
  ;;
  "template")
    X509_OPT="-"
    RETURN=$($echo_bin | $timeout_bin $TIMEOUT $OPENSSL s_client -connect $HOST -servername $SNIHOST $STARTTLS 2>/dev/null | $OPENSSL x509 -noout $X509_OPT 2>/dev/null)

    if [ "$RETURN" == "" ]; then
    # no certificate attribute or other error (could not connect?) send 0 to zabbix, exit 1
      echo ""
      exit 1
    else
    # certificate attribute received send it to zabbix, exit 0
      echo $RETURN 
      exit 0
    fi
  ;;
  *)
    # User supplied unsupported Check Type, exit 1 (error for console)
    exit 1
  ;;
esac
