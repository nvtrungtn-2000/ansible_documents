#!/bin/bash
# ========================================================================================
# CPU Utilization Statistics plugin for Nagios 
#
# Written by	: Andreas Baess based on a script by Steve Bosek
# And made slightly better by Warren Turner @ Paytronix (Now returns top 5 processes on warning/critical)
# Release	: 1.1
# Creation date : 3 May 2008
# Package       : DTB Nagios Plugin
# Description   : Nagios plugin (script) to check cpu utilization statistics.
#		This script has been designed and written on Unix plateform (Linux, Aix, Solaris), 
#		requiring iostat as external program. The locations of these can easily 
#		be changed by editing the variables $IOSTAT at the top of the script. 
#		The script is used to query 4 of the key cpu statistics (user,system,iowait,idle)
#		at the same time. 
#
# Usage         : ./check_cpu.sh [-w <warn>] [-c <crit]
#                                [-uw <user_cpu warn>] [-uc <user_cpu crit>]
#                                [-sw <sys_cpu warn>] [-sc <sys_cpu crit>]
#                                [-iw <io_wait_cpu warn>] [-ic <io_wait_cpu crit>]
#                                [-i <intervals in second>] [-n <report number>] 
# ----------------------------------------------------------------------------------------
# ========================================================================================
#
# HISTORY :
#     Release	|     Date	|    Authors	| 	Description
# --------------+---------------+---------------+------------------------------------------
#	1.1	|    03.05.08	| Andreas Baess	| Changed script to use vmstat on Linux because
#               |               |               | iostat does not use integers
#               |               |               | Fixed output to display the IO-wait warning threshhold
# --------------+---------------+---------------+------------------------------------------
#	1.0	|    03.05.08	| Andreas Baess	| Changed script so that thresholds are global
#               |               |               | and output can be parsed by perfprocessing
#               |               |               | changed default warning to 70 critical to 90
# =========================================================================================

# Paths to commands used in this script.  These may have to be modified to match your system setup.

IOSTAT=/usr/bin/iostat

# Nagios return codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

# Plugin parameters value if not define
WARNING_THRESHOLD=${WARNING_THRESHOLD:="1000"}
CRITICAL_THRESHOLD=${CRITICAL_THRESHOLD:="1000"}
INTERVAL_SEC=${INTERVAL_SEC:="1"}
NUM_REPORT=${NUM_REPORT:="3"}
U_CPU_W=${WARNING_THRESHOLD}
S_CPU_W=${WARNING_THRESHOLD}
IO_CPU_W=${WARNING_THRESHOLD}
U_CPU_C=${CRITICAL_THRESHOLD}
S_CPU_C=${CRITICAL_THRESHOLD}
IO_CPU_C=${CRITICAL_THRESHOLD}

# Plugin variable description
PROGNAME=$(basename $0)
RELEASE="Revision 1.0"
AUTHOR="By Warren Turner, based on work from Andreas Baess <ab@gun.de>, based on a work from Steve Bosek (sbosek@mac.com)"

#if [ ! -x $IOSTAT ]; then
#	echo "UNKNOWN: iostat not found or is not executable by the nagios user."
#	exit $STATE_UNKNOWN
#fi

# Functions plugin usage
print_release() {
    echo "$RELEASE $AUTHOR"
}

print_usage() {
	echo ""
	echo "$PROGNAME $RELEASE - CPU Utilization check script for Nagios"
  echo ""
	echo "This plugin will check cpu utilization (user,system,iowait,idle in %)"
  echo ""
	echo "Usage: check_cpu.sh [flags]"
	echo ""
	echo "Flags:"
	echo "  -w  <number> : Global Warning level in % for user/system/io-wait cpu"
	echo "  -uw <number> : Warning level in % for user cpu"
	echo "  -iw <number> : Warning level in % for IO_wait cpu"
	echo "  -sw <number> : Warning level in % for system cpu"
	echo "  -c  <number> : Global Critical level in % for user/system/io-wait cpu"
	echo "  -uc <number> : Critical level in % for user cpu"
	echo "  -ic <number> : Critical level in % for IO_wait cpu"
	echo "  -sc <number> : Critical level in % for system cpu"
	echo "  -i  <number> : Interval in seconds for iostat (default : 1)"
	echo "  -n  <number> : Number report for iostat (default : 3)"
	echo "  -h  Show this page"
	echo ""
    echo "Usage: $PROGNAME"
    echo "Usage: $PROGNAME --help"
    echo ""
}


# Parse parameters
while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help)
            print_usage
            exit $STATE_OK
            ;;
        -v | --version)
                print_release
                exit $STATE_OK
                ;;
        -w | --warning)
                shift
                WARNING_THRESHOLD=$1
		U_CPU_W=$1
		S_CPU_W=$1
		IO_CPU_W=$1
                ;;
        -c | --critical)
               shift
                CRITICAL_THRESHOLD=$1
		U_CPU_C=$1
		S_CPU_C=$1
		IO_CPU_C=$1
                ;;
        -uw | --uwarn)
               shift
		U_CPU_W=$1
                ;;
        -uc | --ucrit)
               shift
		U_CPU_C=$1
                ;;
        -sw | --swarn)
               shift
		S_CPU_W=$1
                ;;
        -sc | --scrit)
               shift
		S_CPU_C=$1
                ;;
        -iw | --iowarn)
               shift
		IO_CPU_W=$1
                ;;
        -ic | --iocrit)
               shift
		IO_CPU_C=$1
                ;;
        -i | --interval)
               shift
               INTERVAL_SEC=$1
                ;;
        -n | --number)
               shift
               NUM_REPORT=$1
                ;;        
        *)  echo "Unknown argument: $1"
            print_usage
            exit $STATE_UNKNOWN
            ;;
        esac
shift
done

# CPU Utilization Statistics Unix Plateform ( Linux,AIX,Solaris are supported )
case `uname` in
#	Linux ) CPU_REPORT=`iostat -c $INTERVAL_SEC $NUM_REPORT |  tr -s ' ' ';' | sed '/^$/d' | tail -1`
#			CPU_USER=`echo $CPU_REPORT | cut -d ";" -f 2`
#			CPU_SYSTEM=`echo $CPU_REPORT | cut -d ";" -f 4`
#			CPU_IOWAIT=`echo $CPU_REPORT | cut -d ";" -f 5`
#			CPU_IDLE=`echo $CPU_REPORT | cut -d ";" -f 6`
#            ;;
 	  AIX )   CPU_REPORT=`iostat -t $INTERVAL_SEC $NUM_REPORT | sed -e 's/,/./g'|tr -s ' ' ';' | tail -1`
      			CPU_USER=`echo $CPU_REPORT | cut -d ";" -f 4`
      			CPU_SYSTEM=`echo $CPU_REPORT | cut -d ";" -f 5`
      			CPU_IOWAIT=`echo $CPU_REPORT | cut -d ";" -f 7`
      			CPU_IDLE=`echo $CPU_REPORT | cut -d ";" -f 6`
            ;;
  	Linux ) CPU_REPORT=`vmstat -n $INTERVAL_SEC $NUM_REPORT | tail -1`
      			CPU_USER=`echo $CPU_REPORT | awk '{ print $13 }'`
      			CPU_SYSTEM=`echo $CPU_REPORT | awk '{ print $14 }'`
      			CPU_IOWAIT=`echo $CPU_REPORT | awk '{ print $16 }'`
      			CPU_IDLE=`echo $CPU_REPORT | awk '{ print $15 }'`
            ;;
  	SunOS ) CPU_REPORT=`iostat -c $INTERVAL_SEC $NUM_REPORT | tail -1`
      			CPU_USER=`echo $CPU_REPORT | awk '{ print $1 }'`
      			CPU_SYSTEM=`echo $CPU_REPORT | awk '{ print $2 }'`
      			CPU_IOWAIT=`echo $CPU_REPORT | awk '{ print $3 }'`
      			CPU_IDLE=`echo $CPU_REPORT | awk '{ print $4 }'`
            ;;
	*) 		echo "UNKNOWN: `uname` not yet supported by this plugin. Coming soon !"
			exit $STATE_UNKNOWN 
	    ;;
	esac

# Return


# Get the top 5 most CPU consuming processes.
COMMAND=`UNIX95= ps -e -o pcpu,comm,pid | sort -n -r | grep -v "%CPU" | head -5`

i=0
j=0
TOPFIVE="Top 5 CPU Processes(cpu%,pname,pid):"   ;
for word in $COMMAND; do
    i=`expr $i + 1`
    j=`expr $j + 1`
    if [[ $i -eq 3 ]]; then
        i=0;
         if [ $j -eq 15 ]; then
          TOPFIVE="$TOPFIVE `echo $word`"  ;
         else
           TOPFIVE="$TOPFIVE `echo $word], `" ;
         fi
      else
          if [ $(($i%3)) -eq 1 ]; then
           TOPFIVE="$TOPFIVE `echo [$word% `" ;
          else
           TOPFIVE="$TOPFIVE `echo $word `" ;
          fi
      fi
done


perfdata="cpu_user=${CPU_USER}%;${U_CPU_W};${U_CPU_C}; cpu_sys=${CPU_SYSTEM}%;${S_CPU_W};${S_CPU_C}; cpu_iowait=${CPU_IOWAIT}%;${IO_CPU_W};${IO_CPU_C}; cpu_idle=${CPU_IDLE}%;"

# I/O Wait and CPU Usage Critical
if [ ${CPU_IOWAIT} -ge ${IO_CPU_C} ] && [ ${CPU_USER} -ge ${U_CPU_C} -o ${CPU_SYSTEM} -ge ${S_CPU_C} ];
then
	echo "CPU I/O Wait and Usage CRITICAL : CPU User=${CPU_USER}% CPU System=${CPU_SYSTEM}% I/O Wait=${CPU_IOWAIT}% Idle=${CPU_IDLE}% ---- $TOPFIVE ---- |$perfdata"
	exit $STATE_CRITICAL
fi

# I/O Wait Only Critical
if [ ${CPU_IOWAIT} -ge ${IO_CPU_C} ];
then
  echo "CPU I/O Wait CRITICAL : I/O Wait=${CPU_IOWAIT}%   [Ok: CPU User=${CPU_USER}% CPU System=${CPU_SYSTEM}% Idle=${CPU_IDLE}%] |$perfdata"
  exit $STATE_CRITICAL
fi

# CPU Usage Only Critical
if [ ${CPU_USER} -ge ${U_CPU_C} -o ${CPU_SYSTEM} -ge ${S_CPU_C} ];
then
  echo "CPU Usage CRITICAL : CPU User=${CPU_USER}% CPU System=${CPU_SYSTEM}%  ---- $TOPFIVE ----  [Ok: I/O Wait=${CPU_IOWAIT}% Idle=${CPU_IDLE}%] |$perfdata"
  exit $STATE_CRITICAL
fi

# I/O Wait and CPU Usage Warning
if [ ${CPU_IOWAIT} -ge ${IO_CPU_W} ] && [ ${CPU_USER} -ge ${U_CPU_W} -o ${CPU_SYSTEM} -ge ${S_CPU_W} ];
then
	echo "CPU I/O Wait and Usage WARNING : CPU User=${CPU_USER}% CPU System=${CPU_SYSTEM}% I/O Wait=${CPU_IOWAIT}% Idle=${CPU_IDLE}% ---- $TOPFIVE ---- |$perfdata"
	exit $STATE_WARNING
fi

# I/O Wait Only Warning
if [ ${CPU_IOWAIT} -ge ${IO_CPU_W} ];
then
  echo "CPU I/O Wait WARNING : I/O Wait=${CPU_IOWAIT}%   [Ok: CPU User=${CPU_USER}% CPU System=${CPU_SYSTEM}% Idle=${CPU_IDLE}%] |$perfdata"
  exit $STATE_WARNING
fi

# CPU Usage Only Warning
if [ ${CPU_USER} -ge ${U_CPU_W} -o ${CPU_SYSTEM} -ge ${S_CPU_W} ];
then
  echo "CPU Usage WARNING : CPU User=${CPU_USER}% CPU System=${CPU_SYSTEM}%  ---- $TOPFIVE ----  [Ok: I/O Wait=${CPU_IOWAIT}% Idle=${CPU_IDLE}%] |$perfdata"
  exit $STATE_WARNING
fi


# If we got this far, everything seems to be OK - IDLE has no threshold
echo "OK : ---- $TOPFIVE ---- CPU User=${CPU_USER}% CPU System=${CPU_SYSTEM}% I/O Wait=${CPU_IOWAIT}% Idle=${CPU_IDLE}% |$perfdata"
exit $STATE_OK
