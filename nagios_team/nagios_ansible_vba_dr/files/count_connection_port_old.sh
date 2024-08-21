#!/bin/sh
# Nagios return codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
PORT=20145
IP=''
WARNING_THRESHOLD=1500
CRITICAL_THRESHOLD=2000
# Parse parameters
while [ $# -gt 0 ]; do
    case "$1" in
        -p | --port)
                shift
                PORT=$1
                ;;
        -h | --ip)
                shift
                IP=$1
                ;;
        -l| --listen)
                shift
                LT=$1
                ;;
        -w | --warning)
                shift
                WARNING_THRESHOLD=$1
                ;;
        -c | --critical)
               shift
                CRITICAL_THRESHOLD=$1
                ;;
        *)  echo "Unknown argument: $1"
            exit $STATE_UNKNOWN
            ;;
        esac
shift
done


#Check open port
LISTEN=(`netstat -ln | grep :$PORT | wc -l`)

# Return
if  [ $LISTEN -eq 0 ] && [ $LT -eq 'L']; then
	echo "No open port $PORT | 'connection '=0;$WARNING_THRESHOLD;$CRITICAL_THRESHOLD;0;0"
	exit $STATE_CRITICAL
fi

#Get port connection
CONNECTIONS1=(`netstat -an | grep $IP:$PORT | grep 'ESTABLISHED' | wc -l`)
CONNECTIONS2=(`netstat -an | grep $IP:$PORT | grep 'TIME_WAIT' | wc -l`)
CONNECTIONS3=(`netstat -an | grep $IP:$PORT | grep 'CLOSE_WAIT' | wc -l`)


if  [ $CONNECTIONS1 -ge $CRITICAL_THRESHOLD ]; then
        echo "Very many connection, connection ESTABLISHED=$CONNECTIONS1, connection TIME_WAIT=$CONNECTIONS2, connection CLOSE_WAIT=$CONNECTIONS3 | 'Connection_Established'=$CONNECTIONS1;$WARNING_THRESHOLD;$CRITICAL_THRESHOLD;0;0, 'Connection_Time_Wait'=$CONNECTIONS2;0;0, 'Connection_Close_Wait'=$CONNECTIONS3;0;0"
        exit $STATE_CRITICAL
elif  [ $CONNECTIONS1 -ge $WARNING_THRESHOLD ]; then
        echo "Many connection, connection ESTABLISHED=$CONNECTIONS1, connection TIME_WAIT=$CONNECTIONS2, connection CLOSE_WAIT=$CONNECTIONS3 | 'Connection_Established'=$CONNECTIONS1;$WARNING_THRESHOLD;$CRITICAL_THRESHOLD;0;0, 'Connection_Time_Wait'=$CONNECTIONS2;0;0, 'Connection_Close_Wait'=$CONNECTIONS3;0;0"
        exit $STATE_WARNING
elif [ $CONNECTIONS1 -eq 0 ]; then
	echo "No connection, connection ESTABLISHED=$CONNECTIONS1, connection TIME_WAIT=$CONNECTIONS2, connection CLOSE_WAIT=$CONNECTIONS3 | 'Connection_Established'=$CONNECTIONS1;$WARNING_THRESHOLD;$CRITICAL_THRESHOLD;0;0, 'Connection_Time_Wait'=$CONNECTIONS2;0;0, 'Connection_Close_Wait'=$CONNECTIONS3;0;0"
        exit $STATE_WARNING
else
        echo "Normal, connection ESTABLISHED=$CONNECTIONS1, connection TIME_WAIT=$CONNECTIONS2, connection CLOSE_WAIT=$CONNECTIONS3 | 'Connection_Established'=$CONNECTIONS1;$WARNING_THRESHOLD;$CRITICAL_THRESHOLD;0;0, 'Connection_Time_Wait'=$CONNECTIONS2;0;0, 'Connection_Close_Wait'=$CONNECTIONS3;0;0"
        exit $STATE_OK
fi

