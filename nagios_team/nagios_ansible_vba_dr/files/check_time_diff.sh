#! /bin/bash

# Copyright (C) 2016 Charles Atkinson
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

# Purpose:
#   Nagios NRPE plug-in to check time difference between the Nagios server
#   and monitored hosts

# Usage:
#   See usage function or use -h option.

# Versions:
#   * Developed on Debian 8 Jessie

# Programmers' notes: error and trap handling:
#   * UNKNOWN and CRITICAL conditions are fatal; finalise() is called.
#   * WARNING conditions do not stop execution; their message(s) are carried
#     forward; any subsequent OK conditions do not change the WARNING level.

# Programmers' notes: variable names and values
#   * Directory names: *_dir.  Their values should not have a trailing /
#   * File names: *_fn
#   * Logicals: *_flag containing values $true or $false.
#   * $buf is a localised scratch buffer

# Programmers' notes: top level function call tree
#    +
#    |
#    +-- initialise
#    |   |
#    |   +-- usage
#    |
#    +-- check_time_diff
#    |
#    +-- finalise
#
# Utility functions called from various places:
#    msg

# General function definitions in alphabetical order

#--------------------------
# Name: check_time_diff
# Purpose: checks the time difference between Nagios server and local
# Arguments: none
# Global variables read: server_epoch_time
# Global variables set:
#   msg
#--------------------------
function check_time_diff {
    local diff local_epoch_time

    # Calculate the time difference
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    local_epoch_time=$(date +%s)
    ((diff=local_epoch_time-server_epoch_time))
    msg="$diff seconds"

    # Output the message in WARNING and CRITICAL cases
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ((diff<0)) && ((diff=-diff))
    if ((diff>=critical_seconds)); then
        msg C "$msg"
    elif ((diff>=warning_seconds)); then
        msg W "$msg"
    fi

}  # end of function check_time_diff

#--------------------------
# Name: finalise
# Purpose: cleans up and exits
# Arguments:
#    $1: return value
#--------------------------
function finalise {
    local my_retval=$1

    # Kill the self-limiting timer process
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    [[ ${self_limiting_pid:-} != '' ]] && kill $self_limiting_pid

    exit $my_retval
}  # end of function finalise

#--------------------------
# Name: initialise
# Purpose: sets up environment, parses command line and sets OS-dependent variables
#--------------------------
function initialise {
    local old_emsg opt_f_flag opt_t_flag regex

    # Configure shell environment
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    export PATH=/usr/local/bin:/usr/sbin:/sbin:/usr/bin:/bin
    IFS=$' \n\t'
    set -o nounset
    shopt -s extglob            # Enable extended pattern matching operators

    # Initialise global string variables
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    default_critical_seconds=3
    default_warning_seconds=2
    msg_lf=$'\n    '
    nagios_rc_critical=2
    nagios_rc_ok=0
    nagios_rc_unknown=3
    nagios_rc_warning=1
    script_name=${0##*/}
    script_version=0.1

    # Initialise global logic variables
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    readonly false=
    readonly true=true

    # Initialise local string variables
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    local args=("$@")
    local emsg=
    local -r uint_regex='^[[:digit:]]+$'
    local -r opt_f_regex='^(euro|iso8601|strict-iso8601|us)$'
    local -r server_time_iso_8601_regex='^[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2} [[:digit:]]{2}:[[:digit:]]{2}:[[:digit:]]{2}$'

    # Initialise local logic variables
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    opt_f_flag=$false
    opt_t_flag=$false

    # Parse command line
    # ~~~~~~~~~~~~~~~~~~
    critical_seconds=$default_critical_seconds
    warning_seconds=$default_warning_seconds
    while getopts :c:f:ht:w:v opt "$@"
    do
        case $opt in
            c )
                critical_seconds=$OPTARG
                ;;
            f )
                opt_f_flag=$true
                server_time_format=$OPTARG
                ;;
            h )
                usage verbose
                exit 0
                ;;
            t )
                opt_t_flag=$true
                server_time=$OPTARG
                ;;
            w )
                warning_seconds=$OPTARG
                ;;
            v )
                echo "$script_name version $script_version"
                exit 0
                ;;
            : )
                emsg+=$msg_lf"Option $OPTARG must have an argument"
                ;;
            * )
                emsg+=$msg_lf"Invalid option '-$OPTARG'"
        esac
    done

    # Check mandatory options and their arguments
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    if [[ $opt_f_flag ]]; then
        if [[ $server_time_format =~ $opt_f_regex ]]; then 
            case $server_time_format in
                euro )
                    emsg+=$msg_lf'Programming error: date_format euro not supported yet'
                    ;;
                strict-iso8601 )
                    emsg+=$msg_lf'Programming error: date_format strict-iso8601 not supported yet'
                    ;;
                us )
                    emsg+=$msg_lf'Programming error: date_format us not supported yet'
            esac
        else
            emsg+=$msg_lf"Invalid -f value: $server_time_format (does not match $opt_f_regex)"
        fi
    else
        emsg+=$msg_lf'Option -f is required'
    fi
    if [[ $opt_t_flag ]]; then
        [[ ! $server_time =~ $server_time_iso_8601_regex ]] \
            && emsg+=$msg_lf"Invalid -t value $server_time (does not match $server_time_iso_8601_regex)"
    else
        emsg+=$msg_lf'Option -t is required'
    fi

    # Check optional options' arguments
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    old_emsg=$emsg
    [[ ! $critical_seconds =~ $uint_regex ]] \
        &&  emsg+=$msg_lf"-c option invalid: $critical_seconds (not a uint)"
    [[ ! $warning_seconds =~ $uint_regex ]] \
        &&  emsg+=$msg_lf"-w option invalid: $warning_seconds (not a uint)"
    if [[ $emsg = $old_emsg ]]; then
        ((warning_seconds>=critical_seconds)) \
            && emsg+=$msg_lf"warning seconds ($warning_seconds) cannot be >= critical seconds ($critical_seconds)"
    fi

    # Test for extra arguments
    # ~~~~~~~~~~~~~~~~~~~~~~~~
    shift $(($OPTIND-1))
    if [[ $* != '' ]]; then
        emsg+=$msg_lf"Invalid extra argument(s) '$*'"
    fi

    # Report any command line errors
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    if [[ $emsg != '' ]]; then
        emsg+=$msg_lf'(use -h option for help)'
        msg U "Command line error(s)$emsg"
    fi

    # Convert server time to epoch
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # From https://assets.nagios.com/downloads/nagioscore/docs/nagioscore/3/en/macrolist.html#shortdatetime
    # $SHORTDATETIME$  Current date/time stamp (i.e. 10-13-2000 00:30:28).
    # Format of date is determined by date_format directive.
    #
    # Presumably "i.e." is misused to mean "for example".
    #
    # From http://nagios.manubulon.com/traduction/docs25en/configmain.html#date_format
    # date_format
    # This option allows you to specify what kind of date/time format Nagios
    # should use in the web interface and date/time macros. Possible options
    # (along with example output) include:
    # Option         Output Format        Sample Output
    # us             MM/DD/YYYY HH:MM:SS  06/30/2002 03:15:00
    # euro           DD/MM/YYYY HH:MM:SS  30/06/2002 03:15:00
    # iso8601        YYYY-MM-DD HH:MM:SS  2002-06-30 03:15:00
    # strict-iso8601 YYYY-MM-DDTHH:MM:SS  2002-06-30T03:15:00 
    # 
    # Only iso8601 is currently supported by this script
    # 
    # @@@ Timezone adjustments pending pilot experience
    server_epoch_time=$(date -d "$server_time" +%s)

}  # end of function initialise

#--------------------------
# Name: msg
# Purpose: generalised messaging interface
# Arguments:
#    $1 class: O, W, C or U indicating OK, Warning, Critical or Unknown
#    $2 message text
# Usage example:
#    msg U 'Invalid command line option'
# Output: messages to stdout
# Returns:
#   Does not return (calls finalise)
#--------------------------
function msg {
    local class message_text my_rc
    local prefix=TIME_DIFF

    # Process arguments
    # ~~~~~~~~~~~~~~~~~
    class="${1:-}"
    message_text="${2:-}"

    # Class-dependent set-up
    # ~~~~~~~~~~~~~~~~~~~~~~
    case "$class" in
        O )
            my_rc=$nagios_rc_ok
            prefix+=' OK'
            ;;
        W )
            my_rc=$nagios_rc_warning
            prefix+=' WARNING'
            ;;
        C )
            my_rc=$nagios_rc_critical
            prefix+=' CRITICAL'
            ;;
        U )
            my_rc=$nagios_rc_unknown
            prefix+=' UNKNOWN'
            ;;
        * )
            my_rc=$nagios_rc_unknown
            prefix+=' UNKNOWN'
            message_text="Programming error: msg: invalid class '$class': '$*'"
    esac

    # Write to stdout
    # ~~~~~~~~~~~~~~~
    echo "$prefix - $message_text"
    finalise $my_rc
}  #  end of function msg

#--------------------------
# Name: usage
# Purpose: prints usage message
#--------------------------
function usage {
    local msg usage

    # Build the messages
    # ~~~~~~~~~~~~~~~~~~
    usage="usage: $script_name [-c seconds] -f format [-h]"
    usage+=$msg_lf'   -t time [-w seconds] [-v]'
    msg='  where:'
    msg+=$'\n'"    -c critical time difference limit in seconds (default $default_critical_seconds)"
    msg+=$'\n'"    -f format of -t value; the Nagios server's date_format value"
    msg+=$'\n       Possible values: euro, iso8601, strict-iso8601 or us'
    msg+=$'\n    -h Prints this help and exits'
    msg+=$'\n    -t time passed by the Nagios server by for example:'
    msg+=$'\n           check_nrpe!check_time_diff!-f iso8601 -t $SHORTDATETIME$'
    msg+=$'\n'"    -w warning time difference limit in seconds (default $default_warning_seconds)"
    msg+=$'\n    -v prints the version and exits'

    # Display the message(s)
    # ~~~~~~~~~~~~~~~~~~~~~~
    echo "$usage" >&2
    if [[ ${1:-} != 'verbose' ]]; then
        echo "(use -h for help)" >&2
    else
        echo "$msg" >&2
    fi
}  # end of function usage

#--------------------------
# Name: main
# Purpose: the main sequence; execution starts here
#--------------------------

# Declare global variables
# ~~~~~~~~~~~~~~~~~~~~~~~~
declare -A warn_n
declare -A crit_n

# Main call sequence
# ~~~~~~~~~~~~~~~~~~
initialise "${@:-}"
check_time_diff
msg O "$msg"

# Should not get here
# ~~~~~~~~~~~~~~~~~~~
echo "$script_name: programming error: reached end of script"
finalise $nagios_rc_unknown
