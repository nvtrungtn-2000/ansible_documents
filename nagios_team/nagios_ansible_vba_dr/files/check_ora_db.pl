#!/usr/bin/perl

# *******************************************************************************
# *
# * check_ora_db   2014-04-04
# *
# * Copyright 2014 (c) Krzysztof Lewandowski (krzysztof.lewandowski@fastmail.fm)
# *
# * Description: Nagios plug-in for Oracle database (tested on 8i/9i/10g/11g). This script can be run remotely from separate monitoring host.
# *              It checks:
# *					a) database status (up/down)
# *					b) listener status
# *					c) session limit count
# *					d) alert.log errors within defined time frame; error list can be customized (number of occurrences and time window)
# *					e) last analyse time (statistics) based on either default auto jobs or list of schemas that should be checked
# *					f) last archivelogs backup time
# *					g) last full database backup time
# *					h) last incremental database backup time
# *					i) last export time - based on nagios export status table (see setup section)
# *					j) last cold backup time - based on nagios cold backup status table  (see setup section)
# *					k) logical standby lag in minutes
# *					l) logical standby gap detection
# *					m) physical standby lag in minutes
# *					n) physical standby gap detection
# *
# *
# * Run 'check_ora_db --help' for full description.
# *
# * Setup:
# *
# * 1. install 10g (or above) oracle client (script uses EZ connect to establish database connection); this client is to be used by check_ora_db script
# *
# * 2. create required database user (nagios), objects and privileges on target databases (see separate script).
# * 
# * 3. if you would like to monitor either exp/expdp backup or cold backup you have to create export/cold backup status tables 
# *    in the target database (see separate script) and modify your backup scripts to insert return code to nagios status tables as follows:
# * 
# *		Unix:
# *		=====
# *
# *					Export:
# *					-------
# *					expdp backupuser/pass directory=BACKUPDIR dumpfile=${DUMPFILE} logfile=${LOGFILE} content=all full=Y
# *					RC=$?
# *					EXPSTATUS="ERROR"
# *					if [ $(grep "successfully completed at" ${BACKUPDIR}/${LOGFILE} | wc -l) -gt 0 ]
# *					then
# *					  EXPSTATUS="OK"
# *					fi
# *					sqlplus -s nagios/nagiospass <<EOF 2>/dev/null 1>/dev/null
# *					insert into exp_job_details values ('expdp',$RC,'$EXPSTATUS',sysdate);
# *					commit;
# *					delete from exp_job_details where exp_date<sysdate-40;
# *					commit;
# *					EOF
# *
# *		Windows:
# *		========
# *
# *					Export:
# *					-------
# *
# *					a) create c:\oracle\backup\update_exp_status.sql script:
# *					set feedback off echo off termout off
# *					insert into exp_job_details values ('expdp',&1.,'&2.',sysdate);
# *					commit;
# *					delete from exp_job_details where exp_date<sysdate-40;
# *					commit;
# *					exit;
# *
# *					b) modify export script:
# *					expdp backupuser/pass full=Y directory=export dumpfile=%ORACLE_SID%_expdp_%data%.dmp logfile=%ORACLE_SID%_expdp_%data%.log
# *					set LOGFILE=c:\oracle\backup\%ORACLE_SID%_expdp_%data%.log
# *					set RC=0
# *					set LINEOK=
# *					for /F "delims=" %%i IN ('findstr /C:"successfully completed" %LOGFILE%') DO set LINEOK=%%i
# *					set EXPSTATUS=OK
# *					if "%LINEOK%" EQU "" (
# *						set RC=1
# *						set EXPSTATUS=ERROR
# *					)
# *					sqlplus -s nagios/nagiospass @c:\oracle\backup\update_exp_status.sql %RC% %EXPSTATUS%
# *
# *
# *					Cold backup:
# *					------------
# *
# *					a) create c:\oracle\backup\update_coldbackup_status.sql script:
# *					set feedback off echo off termout off
# *					insert into coldbackup_job_details values (&1.,'&2.',sysdate);
# *					commit;
# *					delete from coldbackup_job_details where backup_date<sysdate-40;
# *					commit;
# *					exit;
# *
# *					b) modify backup script:
# *					ntbackup (...)
# *					if errorlevel 1 (
# *					   set RC=1
# *					   set BCKSTATUS=ERROR
# *					   
# *					) else (
# *					   set RC=0
# *					   set BCKSTATUS=OK
# *					)
# *                 rem (startup database)
# *					sqlplus -s nagios/nagiospass @c:\oracle\backup\update_coldbackup_status.sql %RC% %EXPSTATUS%
# *
# * 
# * 4. edit nrpe.cfg and insert required checks with options, for example:
# * 
# *    Note: <ORACLE_HOME> below points to oracle client binaries used by nagios plugin. It's not $ORACLE_HOME of monitored database SID.
# *
# *    command[check_WHATEVER_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=statusOK
# *    command[check_dbstatus_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=dbstatus --service=<SID|SERVICE> --oh=<ORACLE_HOME> --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost>
# *    command[check_lsnrstatus_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=lsnrstatus --service=<SID|SERVICE> --oh=<ORACLE_HOME> --lsnrports=<dbhost>:<dbport_1>,<dbhost>:<dbport_2>
# *    command[check_sessionlimit_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=sessionlimit --service=<SID|SERVICE> --oh=<ORACLE_HOME> --warning=85 --critical=95 --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost>
# *    command[check_alertlogerror_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=alertlogerror --service=<SID|SERVICE> --oh=<ORACLE_HOME> --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost>
# *    command[check_alertlogerror_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=alertlogerror --service=<SID|SERVICE> --oh=<ORACLE_HOME> --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost> --alertlogerrlist=ORA-04045:1::4,ORA-04098::1:4,ORA-27:::24
# *    command[check_laststats_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=laststats --service=<SID|SERVICE> --oh=<ORACLE_HOME> --warning=7 --critical=14 --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost> --statsTarget=auto_job
# *    command[check_laststats_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=laststats --service=<SID|SERVICE> --oh=<ORACLE_HOME> --warning=7 --critical=14 --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost> --statsTarget=DBA_TAB_STATS_HISTORY
# *    command[check_laststats_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=laststats --service=<SID|SERVICE> --oh=<ORACLE_HOME> --warning=7 --critical=14 --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost> --statsTarget=USER1,USER2
# *    command[check_lastArchBackup_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=lastArchBackup --service=<SID|SERVICE> --oh=<ORACLE_HOME> --warning=8 --critical=24 --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost>
# *    command[check_lastFullBackup_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=lastFullBackup --service=<SID|SERVICE> --oh=<ORACLE_HOME> --warning=33 --critical=36 --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost>
# *    command[check_lastIncrBackup_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=lastIncrBackup --service=<SID|SERVICE> --oh=<ORACLE_HOME> --warning=1.5 --critical=2 --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost>
# *    command[check_lastExpBackup_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=lastExpBackup --service=<SID|SERVICE> --oh=<ORACLE_HOME> --warning=1 --critical=3 --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost>
# *    command[check_lastColdBackup_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=lastColdBackup --service=<SID|SERVICE> --oh=<ORACLE_HOME> --warning=1 --critical=3 --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost>
# *    command[check_logstbyLag_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=logstbyLag --service=<SID|SERVICE> --oh=<ORACLE_HOME> --warning=60 --critical=180 --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost>
# *    command[check_logstbyGap_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=logstbyGap --service=<SID|SERVICE> --oh=<ORACLE_HOME> --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost>
# *    command[check_phystbyLag_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=phystbyLag --service=<SID|SERVICE> --oh=<ORACLE_HOME> --warning=60 --critical=180 --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost>
# *    command[check_phystbyGap_SID]=/usr/lib64/nagios/plugins/check_ora_db --action=phystbyGap --service=<SID|SERVICE> --oh=<ORACLE_HOME> --dbuser=nagios --dbpass=<nagiospass> --port=<dbport> --host=<dbhost>
# *
# * 5. reload nrpe daemon and configure appropriate checks on nagios server
# *
# * 
# * Examples:
# * 
# * /usr/lib64/nagios/plugins/check_ora_db --action=statusOK
# * [OK] This is dummy entry
# * 
# * /usr/lib64/nagios/plugins/check_ora_db --action=dbstatus --service=orcl.world --oh=/oracle/orahome --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost
# * [OK] orcl.world-> database is up (version 11.2.0.3.0)
# * 
# * /usr/lib64/nagios/plugins/check_ora_db --action=lsnrstatus --service=orcl.world --oh=/oracle/orahome --lsnrports=orahost:1521,orahost:1542
# * [CRITICAL] Listener status (Host:Port orahost:1521 - OK) (Host:Port orahost:1542 - CRITICAL)
# * 
# * /usr/lib64/nagios/plugins/check_ora_db --action=sessionlimit --service=orcl.world --oh=/oracle/orahome --warning=85 --critical=95 --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost
# * [OK] orcl.world-> Sessions = 1514 : MaxSessions = 7552 (20.05%) :: Warning/Critical = 85%/95%
# * 
# * Alertlog handling:
# * /usr/lib64/nagios/plugins/check_ora_db --action=alertlogerror --service=orcl.world --oh=/oracle/orahome --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost
# *   a) [OK] orcl.world-> AlertLog Errors: 5 : ORA-28(3)[OK],ORA-3136(2)[OK]
# *   b) [OK] orcl.world-> AlertLog Errors: 0
# *   c) [WARNING] orcl.world-> AlertLog Errors: 6 : ORA-00060(3)[Warning],ORA-01555(1)[OK],ORA-3136(1)[OK],ORA-609(1)[OK last: 18.6h ago]
# *      This output shows that during last 24h hours there where three ORA-00060 that triggers warning; one ORA-01555 and ORA-3136 that are ignored; and one ORA-609 that by default triggers warning during last 3 hours; here it was earlier so status is OK
# *
# * /usr/lib64/nagios/plugins/check_ora_db --action=alertlogerror --service=orcl.world --oh=/oracle/orahome --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost --alertlogerrlist=ORA-04045:1::4,ORA-04098::1:4,ORA-27:::24
# * [OK] orcl.world-> AlertLog Errors: 2 : ORA-12012(2)[OK]
# *      here the meaning of "ORA-04045:2::4,ORA-04098::1:4,ORA-27:::24" parameter is as follows:
# *        ORA-04045:1::4 - trigger WARNING if at least 2 errors found during last 4 hours
# *        ORA-04098::1:4 - trigger CRITICAL if at least 1 errors found during last 4 hours
# *        ORA-27:::24 - ignore any occurrence
# *      ORA-12012 is ignored by default
# *
# * Statistics handling:
# * a) 'auto_job' means default oracle statistics job (AUTOTASK for 11g or GATHER_STATS_JOB job for 10g)
# *    /usr/lib64/nagios/plugins/check_ora_db --action=laststats --service=orcl.world --oh=/oracle/orahome --warning=7 --critical=14 --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost --statsTarget=auto_job
# *    [OK] orcl.world-> Statistics: (AUTO_JOB 6/12 OK) :: Warning/Critical = 7/14 days
# * b) 'DBA_TAB_STATS_HISTORY' means force the script to check last updates (gathered statistics) in DBA_TAB_STATS_HISTORY table - use when default auto_job is disabled and you want to check if any statistics are gathered (10g/11g)
# *    /usr/lib64/nagios/plugins/check_ora_db --action=laststats --service=orcl.world --oh=/oracle/orahome --warning=7 --critical=14 --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost --statsTarget=DBA_TAB_STATS_HISTORY
# *    [OK] orcl.world-> Statistics: (DBA_TAB_STATS_HISTORY 312/642 OK) :: Warning/Critical = 7/14 days
# * c) list of schemas that should be checked against statistics gathering
# *    /usr/lib64/nagios/plugins/check_ora_db --action=laststats --service=orcl.world --oh=/oracle/orahome --warning=7 --critical=14 --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost --statsTarget=USER1,USER2
# *    [OK] orcl.world-> Statistics: (USER1 23/30 OK) (USER2 26/37 OK) :: Warning/Critical = 7/14 days
# * 
# * /usr/lib64/nagios/plugins/check_ora_db --action=lastArchBackup --service=orcl.world --oh=/oracle/orahome --warning=8 --critical=24 --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost
# * [OK] orcl.world-> Archivelogs: 20 backups in last 8 hour(s) : 53 backups in last 24 hours
# * 
# * /usr/lib64/nagios/plugins/check_ora_db --action=lastFullBackup --service=orcl.world --oh=/oracle/orahome --warning=33 --critical=36 --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost
# * [OK] orcl.world-> DB FULL backup: 1 backup(s) in last 33 day(s) : 2 backups in last 36 days
# * 
# * /usr/lib64/nagios/plugins/check_ora_db --action=lastIncrBackup --service=orcl.world --oh=/oracle/orahome --warning=1.5 --critical=2 --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost
# * [OK] orcl.world-> DB INCR backup: 1 backup(s) in last 1.5 day(s) : 1 backups in last 2 days
# * 
# * /usr/lib64/nagios/plugins/check_ora_db --action=lastExpBackup --service=orcl.world --oh=/oracle/orahome --warning=1 --critical=3 --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost
# * [OK] orcl.world-> Database export: 1 export(s) in last 1 day(s) : 3 exports in last 3 days
# * 
# * /usr/lib64/nagios/plugins/check_ora_db --action=lastColdBackup --service=orcl.world --oh=/oracle/orahome --warning=1 --critical=3 --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost
# * [OK] orcl.world-> Database cold backup: 1 backup(s) in last 1 day(s) : 3 backups in last 3 days
# * 
# * /usr/lib64/nagios/plugins/check_ora_db --action=logstbyLag --service=orcl.world --oh=/oracle/orahome --warning=60 --critical=180 --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost
# * [OK] orcl.world-> Latest committed transactions time (from primary): 2014-04-04 10:22:31 - Lag: 4 minutes :: Warning/Critical = 60/180 min
# * 
# * /usr/lib64/nagios/plugins/check_ora_db --action=logstbyGap --service=orcl.world --oh=/oracle/orahome --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost
# * [OK] orcl.world-> No GAP detected
# * 
# * /usr/lib64/nagios/plugins/check_ora_db --action=phystbyLag --service=orcl.world --oh=/oracle/orahome --warning=60 --critical=180 --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost
# * [OK] orcl.world-> Lag: 15 minutes :: Warning/Critical = 60/180 min
# * 
# * /usr/lib64/nagios/plugins/check_ora_db --action=phystbyGap --service=orcl.world --oh=/oracle/orahome --dbuser=nagios --dbpass=nagiospass --port=1521 --host=orahost
# * [OK] orcl.world-> No GAP detected
# * 
# *******************************************************************************

use Sys::Hostname;
use File::Basename;
use Time::localtime;
use Time::Local;
use Getopt::Long qw/GetOptions/;
Getopt::Long::Configure(qw/ no_ignore_case pass_through /);
use File::Temp qw/tempfile tempdir/;
File::Temp->safe_level( File::Temp::MEDIUM );

use vars qw/ %opt $osname $host $query $output $output_msg $status %nagios_exit_codes $path_separator $nl_separator $tdir $dbver/;
use vars qw/ %parerrlist $pwarn $pcrit $ptrig $oerr $onum $otime/;

%nagios_exit_codes = ( 'UNKNOWN', 3, 'OK', 0, 'WARNING', 1, 'CRITICAL', 2 );
$output_msg = '';
$status = 'OK';

$opt{warning} = 85;
$opt{critical} = 95;
$opt{defaultport} = 1521;
$opt{port} = $opt{defaultport};
$opt{timeout} = 60;
# Put Nagios dbuser password here, otherwise provide it as command parameter
$opt{dbpass} = 'nagiospass'; 

$tdir = '/tmp';
our $ME = basename($0);

$osname = "$^O";
$path_separator = "\\";
$path_separator = '/' if $osname !~ /MSWin/i;
$nl_separator = "\r\n";
$nl_separator = "\n" if $osname !~ /MSWin/i;

die "Wrong parameters! Type '$0 --help' for help!" if ! @ARGV;

GetOptions(
    \%opt,
    'help|h',
    'action|a=s',
    'lsnrports=s',
    'statsTarget=s',
    'alertlogerrlist=s',
    'oracle_home|oh=s',
    'oracle_sid|sid|service=s',
    'warning=f',
    'critical=f',
    'host|h=s',
    'port=i',
    'dbuser|u=s',
    'dbpass|p=s',
    'timeout=i'
);

$opt{host} = hostname if not exists $opt{host};

die "Wrong parameters! Type '$0 --help' for help!" if ! keys %opt and ! @ARGV;

if ($opt{help}) {
    print qq{Usage: $ME <options>
Run various tests against Oracle database.
Returns with an exit code of 0 (ok), 1 (warning), 2 (critical), or 3 (unknown)

Common connection options:
 -h,   --host=NAME         hostname to connect to; defaults to localhost
       --port=NUM          port to connect to; defaults to $opt{defaultport}
 -sid, --oracle_sid=NAME   database name to connect to (ORACLE_SID)
 -oh,  --oracle_home=NAME  ORACLE_HOME path
 -u,   --dbuser=NAME       database user to connect as; defaults to '/ as sysdba'
 -p,   --dbpass=PASS       database password; ignored for '/ as sysdba' connection
       --timeout=NUM       waits NUM seconds while executing SQL statement before throwing Timeout error

Other options:
  --critical              critical threshold
  --warning               warning threshold
  --action=ACTION	  currently supports:
                            statusOK       - always returns with OK
                            dbstatus       - checks whether database is OPEN (OK) or not (CRITICAL)
                            lsnrstatus     - checks listener(s) status; use with 'lsnrports' option
                            sessionlimit   - checks if (number of sessions)/(max sessions) exceeded % thresholds
                            alertlogerror  - checks alert.log errors; by default checks any ORA- error in the last 24 hours; can be customized with 'alertlogerrlist' option
								By default the following error handling is set-up (can be overwritten):
									ORA-00600 - triggers CRITICAL for any occurrence during last 3 hours 							
									ORA-07445 - triggers CRITICAL for any occurrence during last 3 hours 							
									ORA-00060 - triggers WARNING if at least 3 errors found during last 2 hours
									ORA-609   - triggers WARNING if at least 3 errors found during last 2 hours
									ORA-01555 - triggers WARNING if at least 4 errors found during last 2 hours
									ORA-28    - ignores any occurrence
									ORA-01013 - ignores any occurrence
									ORA-12012 - ignores any occurrence
									ORA-3136  - ignores any occurrence
									ORA-20011 - ignores any occurrence
									ORA-3214  - ignores any occurrence							
                            lastStats      - checks if statistics were gathered in last N days (use with thresholds); use with 'statsTarget' option
                            lastArchBackup - checks if last successful archivelog backup was done in last N hours (use with thresholds)
                            lastFullBackup - checks if last successful full DB backup was done in last N days (use with thresholds)
                            lastIncrBackup - checks if last successful incremental DB backup was done in last N days (use with thresholds)
                            lastExpBackup  - checks if last successful exp/expdp backup was done in last N days (use with thresholds)
                            lastColdBackup - checks if last successful cold backup was done in last N days (use with thresholds)
                            logstbyLag     - checks Logical Standby lag in minutes (use with thresholds)
                            logstbyGap     - checks Logical Standby gap
                            phystbyLag     - checks Physical Standby lag in minutes (use with thresholds)
                            phystbyGap     - checks Physical Standby gap
  --lsnrports=H1:P1[, ...]  list of host(IP):port pairs to check connection; use with 'lsnrstatus' action
  --statsTarget=U1[, ...]   list of Usernames for which check is performed;
							  or 'auto_job' - means check default oracle statistics job (AUTOTASK for 11g or GATHER_STATS_JOB job for 10g)
							  or 'DBA_TAB_STATS_HISTORY' - means check last updates (gathered statistics) in DBA_TAB_STATS_HISTORY table (10g/11g)
							     - use when default auto_job is disabled and you want to check if any statistics are gathered
  --alertlogerrlist=string1[, ...]  list of strings that define ORA- error handling, in format 'stringX'=E:W:C:T, where:
                                        E = num - ORA-num
                                        W = num - minimal number of occurrences that trigger warning event
                                        C = num - minimal number of occurrences that trigger critical event
                                        T = num - checks last 'T' hours in alert.log
  -h, --help              display this help information

};
    exit 0;
}


######################################
## Subprograms
######################################

sub my_exit {
    my ($estatus, $msg) = @_;

    chomp $msg;
    print "[${estatus}] $msg\n";
    exit $nagios_exit_codes{ $estatus };
}


sub exec_sql {
    my ($sql) = @_;
    my ($fh, $tmpfile, $sqlout, $connectstring, $errline);

    $connectstring = '"/ as sysdba"';
    $connectstring = "$opt{dbuser}/$opt{dbpass}\@$opt{host}:$opt{port}\/$opt{oracle_sid}" if defined $opt{dbuser};

    ($fh,$tmpfile) = tempfile("tmp.${ME}.XXXXXXXX", SUFFIX => '.sql', DIR => $tdir);
    printf $fh qq[
set echo off define on heading off pagesize 0
set linesize 150
$sql
exit
];
    close $fh or die "Cannot close temporary sql file!";

    eval {
      local $SIG{ALRM} = sub { die "alarm\n" };
      alarm $opt{timeout};
      $sqlout = qx[$opt{oracle_home}${path_separator}bin${path_separator}sqlplus -L -s $connectstring \@${tmpfile}];
    };
    
    if ($@) {
        unlink $tmpfile;
	my_exit( 'CRITICAL', "Unexpected error while executing SQL statement!" )  unless $@ eq "alarm\n";
    	# timed out
        my_exit( 'CRITICAL', "Time out ($opt{timeout} seconds) while executing SQL statement!" );
    }
    alarm 0;

    unlink $tmpfile;
    $sqlout =~ s/^\s*\n//gs; $sqlout =~ s/^\s+//g; $sqlout =~ s/\s+$//g;

    if( $opt{action} ne 'alertlogerror' ) {
      $errline = ''; $errline = $1 if $sqlout =~ m/(ORA\-[^\n]+)/gs;
      my_exit( 'CRITICAL', "Oracle error: $errline" ) if( $errline );
    }

    return $sqlout;
}


######################################
## The real stuff 
######################################

$opt{action} = lc $opt{action};

my_exit( 'OK', 'This is dummy entry' ) if $opt{action} eq 'statusok';

die "ORACLE_SID not provided! Type '$0 --help' for help!" if ! defined $opt{oracle_sid};
die "ORACLE_HOME not provided! Type '$0 --help' for help!" if ! defined $opt{oracle_home};

$ENV{ORACLE_SID} = $opt{oracle_sid};
$ENV{ORACLE_HOME} = $opt{oracle_home};
delete $ENV{TWO_TASK};

#
# listener status check

if( $opt{action} eq 'lsnrstatus' ){

  die "'lsnrstatus' must be folowed by 'lsnrports' option! Type '$0 --help' for help!" if ! defined $opt{lsnrports};

  $output_msg = 'Listener status ';
  foreach my $entry (split /,/, $opt{lsnrports}) {
    my ($lsnrhost, $lsnrport) = split /:/, $entry;
    die "Listener host and listener port pairs must be provided! Type '$0 --help' for help!" if !( defined $lsnrhost && defined $lsnrport);
    $output = qx[$opt{oracle_home}${path_separator}bin${path_separator}tnsping $lsnrhost:$lsnrport\/$opt{oracle_sid}];
    if( $output !~ m/OK \(\d+/ ) {
      $status = 'CRITICAL';
      $output_msg .= "(Host:Port $lsnrhost:$lsnrport - CRITICAL) ";
    } else {
      $output_msg .= "(Host:Port $lsnrhost:$lsnrport - OK) "
    }
  }

  my_exit( $status, $output_msg );
}

#
# initial database status check

#die "You must provide both dbuser and dbpass parameters or none! Type '$0 --help' for help!"
#  if!( (exists $opt{dbuser} and exists $opt{dbpass}) || (! exists $opt{dbuser} and ! exists $opt{dbpass}) );

$query = qq[COLUMN l_output FORMAT A20
SELECT i.status AS l_output FROM v\$instance i;
];

$output = exec_sql( $query );

my_exit( 'CRITICAL', "$opt{oracle_sid}-> database is down!" ) if( "$output" ne "OPEN" );

#
# check db version

$query = qq[COLUMN l_output FORMAT A20
SELECT i.VERSION AS l_output FROM v\$instance i;
];

$dbver = exec_sql( $query );

#
# check action provided  

if( $opt{action} eq 'dbstatus' ){
  my_exit( 'OK', "$opt{oracle_sid}-> database is up (version $dbver)" );
}
elsif( $opt{action} eq 'sessionlimit' ) {

  $query = qq[col sesslimit format 999999
col cursess format 999999
select (select value from v\$parameter where name='sessions') sesslimit, (select count(*) from v\$session) cursess from dual;
];

  $output = exec_sql( $query );
  
  ($sesslimit, $cursess) = split /\s+/, $output;
  $rounded_sesslimit_perc = sprintf("%.2f", ( $cursess / $sesslimit )*100 );

  $output_msg = "$opt{oracle_sid}-> Sessions = $cursess : MaxSessions = $sesslimit (${rounded_sesslimit_perc}%) :: Warning/Critical = $opt{warning}%/$opt{critical}%";
  $status = 'WARNING' if ( $rounded_sesslimit_perc >= $opt{warning} && $rounded_sesslimit_perc < $opt{critical} );
  $status = 'CRITICAL' if ( $rounded_sesslimit_perc >= $opt{critical} );
}
elsif( $opt{action} eq 'alertlogerror' ) {

  $dbver = $1 if $dbver =~ /^(\d+)/;
  $subq = "";
  $opt{alertlogerrlist} = "ORA-00600:0:1:3,ORA-07445:0:1:3,ORA-28:::24,ORA-609:3::2,ORA-01013:::24,ORA-12012:::24,ORA-3136:::24,ORA-00060:3::24,ORA-20011:::24,ORA-01555:4::24,ORA-3214:::24," . $opt{alertlogerrlist}; 
  $opt{alertlogerrlist} =~ s/,$//;

  if( $dbver >= 10 ) {

    $query = qq[col outputline for a300 
select nvl(
(SELECT sumerrors ||' : '|| SUBSTR (SYS_CONNECT_BY_PATH (altext||':'||acnt||':'||trim(to_char(last_err_hours,'990.9')), ','), 2)
      FROM (select altext, acnt, round(24*(sysdate-last_err_date),1) last_err_hours, sum(acnt) over () sumerrors,ROW_NUMBER () OVER (ORDER BY altext ) rn, count(*) over () cnt from (
                SELECT regexp_substr(alert_text,'ORA-\\d+') altext, COUNT (*) acnt, to_date(to_char(max(alert_date),'YYYY-MM-DD HH24:MI:SS'),'YYYY-MM-DD HH24:MI:SS') last_err_date
              FROM sys.alert_log where alert_date > sysdate-1 and alert_text like '%%ORA-%' group by regexp_substr(alert_text,'ORA-\\d+')))
     WHERE rn = cnt
START WITH rn = 1
CONNECT BY rn = PRIOR rn + 1),0) outputline
from dual;
];

    %parerrlist = ();
    map { $parerrlist{$1} = $2 if /(ORA\-\d+):(.+)/; } split /,/, $opt{alertlogerrlist};

    $output = exec_sql( $query );
   
    $parsedoutput = "0"; $parsedoutput = "$1" if $output =~ /^(\d+\s+:\s+)/; $output =~ s/^\d+\s+:\s+//;
    if( $parsedoutput ne "0" ) {
    foreach my $outerrline (split /,/, $output) {
      ($oerr, $onum, $otime) = split /:/, $outerrline;
      if( exists $parerrlist{$oerr} ) {
        $parsedoutput .= "${oerr}(${onum})";
        ($pwarn, $pcrit, $ptrig) = split /:/, $parerrlist{$oerr};
        if( $otime <= $ptrig ) {
          if( $pcrit ne "" && $onum >= $pcrit ) {
            $status = 'CRITICAL';
            $parsedoutput .= "[Critical]";
          }
          elsif( $pwarn ne "" && $onum >= $pwarn ) {
            $status = 'WARNING' if $status ne 'CRITICAL';
            $parsedoutput .= "[Warning]";
          }
          else { $parsedoutput .= "[OK]"; }
        }
        else {
          $parsedoutput .= "[OK last: ${otime}h ago]";
        }
        $parsedoutput .= ",";
      }
      else {
        $parsedoutput .= "${oerr}(${onum})[Warning],";
        $status = 'WARNING' if $status ne 'CRITICAL';
      }
    }
    }

    $parsedoutput =~ s/,$//;
    $output_msg = "$opt{oracle_sid}-> AlertLog Errors: $parsedoutput";
  }
  else {
    $query = qq[col cnt for 999999 
select count(*) cnt from sys.alert_log where alert_date > sysdate-1 and alert_text like '%%ORA-%';
];

    $output = exec_sql( $query );
    ($numalerts, $rest) = split /:/, $output;

    $status = 'WARNING' if $numalerts != 0;
    $output_msg = "$opt{oracle_sid}-> AlertLog Errors: $output";
  }

}
elsif( $opt{action} eq 'lastarchbackup' ) {

  $dbver = $1 if $dbver =~ /^(\d+)/;

  if( $dbver >= 10 ) {
    $query = qq[col cnt_ok for 999999 
col cnt_warning for 999999
select /*+ RULE */ (case when (select count(*) cnt from V\$RMAN_BACKUP_JOB_DETAILS where INPUT_TYPE='ARCHIVELOG' and status='COMPLETED'
  and START_TIME>sysdate-$opt{warning}/24)>0 then (select count(*) cnt from V\$RMAN_BACKUP_JOB_DETAILS where INPUT_TYPE='ARCHIVELOG' and status='COMPLETED'
  and START_TIME>sysdate-$opt{warning}/24) else (select count(*) from v\$backup_set bs, v\$backup_piece bp
   where bs.set_stamp = bp.set_stamp and bs.set_count  = bp.set_count and bp.status = 'A' and bs.backup_type='L'
   and bp.completion_time>sysdate-$opt{warning}/24) end) cnt_ok,
       (case when (select count(*) cnt from V\$RMAN_BACKUP_JOB_DETAILS where INPUT_TYPE='ARCHIVELOG' and status='COMPLETED'
  and START_TIME>sysdate-$opt{critical}/24)>0 then (select count(*) cnt from V\$RMAN_BACKUP_JOB_DETAILS where INPUT_TYPE='ARCHIVELOG' and status='COMPLETED'
  and START_TIME>sysdate-$opt{critical}/24) else (select count(*) from v\$backup_set bs, v\$backup_piece bp
   where bs.set_stamp = bp.set_stamp and bs.set_count  = bp.set_count and bp.status = 'A' and bs.backup_type='L'
   and bp.completion_time>sysdate-$opt{critical}/24) end) cnt_warning
from dual;
];
  } else {
    $query = qq[col cnt_ok for 999999
col cnt_warning for 999999
select (select count(*) from v\$backup_set bs, v\$backup_piece bp
   where bs.set_stamp = bp.set_stamp and bs.set_count  = bp.set_count and bp.status = 'A' and bs.backup_type='L'
   and bp.completion_time>sysdate-$opt{warning}/24) cnt_ok,
       (select count(*) from v\$backup_set bs, v\$backup_piece bp
   where bs.set_stamp = bp.set_stamp and bs.set_count  = bp.set_count and bp.status = 'A' and bs.backup_type='L'
   and bp.completion_time>sysdate-$opt{critical}/24) cnt_warning
from dual;
];
  }

  $output = exec_sql( $query );
  ($cnt_ok, $cnt_warning) = split /\s+/, $output;

  $output_msg = "$opt{oracle_sid}-> Archivelogs: $cnt_ok backups in last $opt{warning} hour(s) : $cnt_warning backups in last $opt{critical} hours";
  $status = 'WARNING' if $cnt_ok == 0 && $cnt_warning > 0; 
  $status = 'CRITICAL' if $cnt_ok == 0 && $cnt_warning == 0;
}
elsif( $opt{action} eq 'lastfullbackup' || $opt{action} eq 'lastincrbackup' ) {

  $backuptype='FULL';
  $backuptype='INCR' if $opt{action} eq 'lastincrbackup';

  $dbver = $1 if $dbver =~ /^(\d+)/;

  if( $dbver >= 10 ) {
    $query = qq[col cnt_ok for 999999
col cnt_warning for 999999
select /*+ RULE */ (select count(*) cnt from V\$RMAN_BACKUP_JOB_DETAILS where INPUT_TYPE='DB ${backuptype}' and status in ('COMPLETED','COMPLETED WITH WARNINGS')
  and START_TIME>sysdate-$opt{warning}-2/24) cnt_ok,
       (select count(*) cnt from V\$RMAN_BACKUP_JOB_DETAILS where INPUT_TYPE='DB ${backuptype}' and status in ('COMPLETED','COMPLETED WITH WARNINGS')
  and START_TIME>sysdate-$opt{critical}-2/24) cnt_warning
from dual;
];
  } else {

    $subq = "";
    $subq = "not " if $opt{action} eq 'lastincrbackup';

    $query = qq[col cnt_ok for 999999
col cnt_warning for 999999
select (select count(*)
   from v\$backup_set bs, v\$backup_piece bp
   where bs.set_stamp = bp.set_stamp and bs.set_count  = bp.set_count
   and (bp.set_stamp,bp.set_count) in (select set_stamp,set_count from V\$BACKUP_DATAFILE where file#>0 and INCREMENTAL_LEVEL is $subq null)
   and bp.status = 'A' and bp.completion_time>sysdate-$opt{warning}-2/24) cnt_ok,
       (select count(*)
   from v\$backup_set bs, v\$backup_piece bp
   where bs.set_stamp = bp.set_stamp and bs.set_count  = bp.set_count
   and (bp.set_stamp,bp.set_count) in (select set_stamp,set_count from V\$BACKUP_DATAFILE where file#>0 and INCREMENTAL_LEVEL is $subq null)
   and bp.status = 'A' and bp.completion_time>sysdate-$opt{critical}-2/24) cnt_warning
from dual;
];
  }

  $output = exec_sql( $query );
  ($cnt_ok, $cnt_warning) = split /\s+/, $output;

  $output_msg = "$opt{oracle_sid}-> DB $backuptype backup: $cnt_ok backup(s) in last $opt{warning} day(s) : $cnt_warning backups in last $opt{critical} days";
  $status = 'WARNING' if $cnt_ok == 0 && $cnt_warning > 0;
  $status = 'CRITICAL' if $cnt_ok == 0 && $cnt_warning == 0;
}
elsif( $opt{action} eq 'lastexpbackup' ) {

  $query = qq[col cnt_ok for 999999
col cnt_warning for 999999
select (select count(*) cnt from exp_job_details where exp_status='OK'
  and exp_date>sysdate-$opt{warning}-2/24) cnt_ok,
       (select count(*) cnt from exp_job_details where exp_status='OK'
  and exp_date>sysdate-$opt{critical}-2/24) cnt_warning
from dual;
];

  $output = exec_sql( $query );
  ($cnt_ok, $cnt_warning) = split /\s+/, $output;

  $output_msg = "$opt{oracle_sid}-> Database export: $cnt_ok export(s) in last $opt{warning} day(s) : $cnt_warning exports in last $opt{critical} days";
  $status = 'WARNING' if $cnt_ok == 0 && $cnt_warning > 0;
  $status = 'CRITICAL' if $cnt_ok == 0 && $cnt_warning == 0;  
}
elsif( $opt{action} eq 'lastcoldbackup' ) {

  $query = qq[col cnt_ok for 999999
col cnt_warning for 999999
select (select count(*) cnt from coldbackup_job_details where backup_status='OK'
  and backup_date>sysdate-$opt{warning}-2/24) cnt_ok,
       (select count(*) cnt from coldbackup_job_details where backup_status='OK'
  and backup_date>sysdate-$opt{critical}-2/24) cnt_warning
from dual;
];

  $output = exec_sql( $query );
  ($cnt_ok, $cnt_warning) = split /\s+/, $output;

  $output_msg = "$opt{oracle_sid}-> Database cold backup: $cnt_ok backup(s) in last $opt{warning} day(s) : $cnt_warning backups in last $opt{critical} days";
  $status = 'WARNING' if $cnt_ok == 0 && $cnt_warning > 0;
  $status = 'CRITICAL' if $cnt_ok == 0 && $cnt_warning == 0;
}
elsif( $opt{action} eq 'logstbylag' ) {

  $query = qq[col sql_output for a100
set linesize 100
select 'Latest committed transactions time (from primary): '||to_char(APPLIED_TIME,'yyyy-mm-dd hh24:mi:ss')||' - Lag: '||round((sysdate-APPLIED_TIME)*24*60)||' minutes' sql_output from V\$LOGSTDBY_PROGRESS;
];

  $output = exec_sql( $query );
  $output_msg = "$opt{oracle_sid}-> " . $output . " :: Warning/Critical = $opt{warning}/$opt{critical} min";

  my $delay_min = 100000;
  $delay_min = $1 if $output =~ /.+?Lag: (\d+)/;
  $status = 'WARNING' if ( $delay_min >= $opt{warning} && $delay_min < $opt{critical} );
  $status = 'CRITICAL' if ( $delay_min >= $opt{critical} );
  my_exit( 'CRITICAL', "$opt{oracle_sid}-> Database is not in Logical Standby APPLIED mode" ) if $delay_min == 100000;  
}
elsif( $opt{action} eq 'logstbygap' ) {

  $query = qq[col sql_output for a100
set linesize 100
select 'GAP DETECTED: sequence '||(sequence#_prev+1)||' - '||(sequence#-1) sql_output
from (
  select
  SEQUENCE#, lag(sequence#) over (order by sequence#) as sequence#_prev,sequence#- lag(sequence#) over (order by sequence#) as sequence#_diff
  from DBA_LOGSTDBY_LOG
)
where sequence#_diff > 1;
];

  $output = exec_sql( $query );
  $output_msg = "$opt{oracle_sid}-> No GAP detected";
  my_exit( 'CRITICAL', "$opt{oracle_sid}-> " . $output ) if $output =~ m/GAP DETECTED/;
}
elsif( $opt{action} eq 'phystbylag' ) {

  $query = qq[col delay_min for 9999999 
select round((lreceived.next_time - lapplied.next_time)*24*60,0) delay_min from
    (select rownum, next_time
    from v\$archived_log
    where sequence# = (select max(sequence#) from v\$archived_log where applied='YES')) lapplied,
    (select rownum, next_time
    from v\$archived_log
    where sequence# = (select max(sequence#) from v\$archived_log)) lreceived;
];

  $delay_min = $output = exec_sql( $query );
  $output_msg = "$opt{oracle_sid}-> Lag: $delay_min minutes :: Warning/Critical = $opt{warning}/$opt{critical} min";

  $status = 'WARNING' if ( $delay_min >= $opt{warning} && $delay_min < $opt{critical} );
  $status = 'CRITICAL' if ( $delay_min >= $opt{critical} );
  my_exit( 'UNKNOWN', "$opt{oracle_sid}-> Cannot calculate standby lag" ) if $delay_min !~ /^\d+$/;
}
elsif( $opt{action} eq 'phystbygap' ) {

  $query = qq[col sql_output for a100
set linesize 100
select 'GAP DETECTED: sequence '||LOW_SEQUENCE#||' - '||HIGH_SEQUENCE# sql_output from v\$archive_gap;
];

  $output = exec_sql( $query );
  $output_msg = "$opt{oracle_sid}-> No GAP detected";
  my_exit( 'CRITICAL', "$opt{oracle_sid}-> " . $output ) if $output =~ m/GAP DETECTED/;
}
elsif( $opt{action} eq 'laststats' ) {

  die "'laststats' must be folowed by 'statsTarget' option! Type '$0 --help' for help!" if ! defined $opt{statsTarget};
  $dbver = $1 if $dbver =~ /^(\d+)/;

  $output_msg = "$opt{oracle_sid}-> Statistics: ";
  foreach my $statUser (split /,/, uc $opt{statsTarget}) {

    if( $statUser eq 'AUTO_JOB' ) {

      if( $dbver eq '11' ) {

        $query = qq[col cnt_ok for 999999
col cnt_warning for 999999
select (select count(*) cnt from dba_autotask_job_history where client_name='auto optimizer stats collection' 
          and job_status='SUCCEEDED' and job_start_time > sysdate-$opt{warning}) cnt_ok,
       (select count(*) cnt from dba_autotask_job_history where client_name='auto optimizer stats collection' 
          and job_status='SUCCEEDED' and job_start_time > sysdate-$opt{critical}) cnt_warning
from dual;
];
      }
      elsif( $dbver eq '10' ) {

        $query = qq[col cnt_ok for 999999
col cnt_warning for 999999
select (select count(*) cnt from DBA_SCHEDULER_JOB_RUN_DETAILS where job_name='GATHER_STATS_JOB' and status='SUCCEEDED' and log_date > sysdate-$opt{warning}) cnt_ok,
       (select count(*) cnt from DBA_SCHEDULER_JOB_RUN_DETAILS where job_name='GATHER_STATS_JOB' and status='SUCCEEDED' and log_date > sysdate-$opt{critical}) cnt_warning
from dual;
];
      }
      else {
        my_exit( 'CRITICAL', "$opt{oracle_sid}-> AUTO_JOB is not defined for Oracle $dbver !" );
      }
    }
    elsif ( $statUser eq 'DBA_TAB_STATS_HISTORY' ) {

      $query = qq[col cnt_ok for 999999
col cnt_warning for 999999
select (select count(*) cnt from DBA_TAB_STATS_HISTORY where owner<>'SYS' and stats_update_time > sysdate-$opt{warning}) cnt_ok,
       (select count(*) cnt from DBA_TAB_STATS_HISTORY where owner<>'SYS' and stats_update_time > sysdate-$opt{critical}) cnt_warning
from dual;
];
    } 
    else {

      $query = qq[col cnt_ok for 999999
col cnt_warning for 999999
select (select count(*) cnt from dba_tables where owner='$statUser' and last_analyzed > sysdate-$opt{warning}) cnt_ok,
       (select count(*) cnt from dba_tables where owner='$statUser' and last_analyzed > sysdate-$opt{critical}) cnt_warning
from dual;
];
    }

    $output = exec_sql( $query ); 
    ($cnt_ok, $cnt_warning) = split /\s+/, $output;

    if( $cnt_ok =~ m/\d+/ && $cnt_warning =~ m/\d+/ ) {
      $output_msg .= "($statUser ${cnt_ok}/${cnt_warning} ";
      $output_msg .= "OK) " if $cnt_ok > 0;
      $output_msg .= "Warning) " if $cnt_ok == 0 && $cnt_warning > 0;
      $output_msg .= "Critical) " if $cnt_ok == 0 && $cnt_warning == 0;
      $status = 'WARNING' if $cnt_ok == 0 && $cnt_warning > 0 && $status ne 'CRITICAL';
      $status = 'CRITICAL' if $cnt_ok == 0 && $cnt_warning == 0;
    } 
  }

  $output_msg .= ":: Warning/Critical = $opt{warning}/$opt{critical} days";
}
else {
  $status = 'CRITICAL';
  $output_msg = "[<blink><b>Unknown action name provided<\/b><\/blink>]";
}


my_exit( $status, $output_msg );

