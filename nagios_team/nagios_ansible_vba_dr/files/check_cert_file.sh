#!/bin/bash

#duhd 2020

while [ $# -gt 0 ]; do
    case "$1" in
        -w | --warning)
                shift
                WARNING_THRESHOLD=$1
                ;;
        -c | --critical)
               shift
                CRITICAL_THRESHOLD=$1
                ;;
        -k | --keypass)
               shift
                KEY_PASS=$1
                ;;
        -f | --certfile)
               shift
                CERT_FILE=$1
                ;;
        *)  echo "Unknown argument: $1"
            exit 4
            ;;
        esac
shift
done

Pass=$KEY_PASS
Wdays=$WARNING_THRESHOLD
Cdays=$CRITICAL_THRESHOLD
Wtime=$(expr "${Wdays}" \* 86400)
Ctime=$(expr "${Cdays}" \* 86400)


EndDate=$(openssl pkcs12 -in ${CERT_FILE} -password pass:${Pass} -clcerts -nodes | openssl x509 -noout -enddate | awk 'BEGIN { FS="=" } /1/ {print $2}')

OutputDate=$(date -d "${EndDate}" "+%s")
SystemDate=$(date '+%s')

DiffTime=$(expr "${OutputDate}" - "${SystemDate}")
DiffDay=$(expr "${DiffTime}" / 86400)

if [ "${DiffTime}" -lt 0 ]
	then
	echo "ERROR! Certificate or Pass Invalid"
	exit 4
fi

if [ "${DiffTime}" -le ${Ctime} ]
	then
	echo "Certificate is going to expire in less then ${DiffDay} days on ( ${EndDate} )"
	exit 2
elif [ "${DiffTime}" -le ${Wtime} ]
	then
	echo "Certificate is going to expire in less then ${DiffDay} days on ( ${EndDate} )"
	exit 1
elif [ "${DiffTime}" -gt ${Wtime} ]
        then
        echo "Certificate will expire on ${EndDate}"
        exit 0
else
	echo "ERROR! Certificate Invalid!"
	exit 2
fi
