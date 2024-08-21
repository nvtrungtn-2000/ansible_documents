#!/usr/bin/perl

# *******************************************************************************
# *
# * check_asm   2014-01-05
# *
# * Updated:    2015-06-09 - Added performance data plus some improvements
# *
# * Copyright 2014 (c) Krzysztof Lewandowski (krzysztof.lewandowski@fastmail.fm)
# *
# * Description: Nagios plug-in for Oracle ASM instance (11g and above)
# *              It checks:
# *                                     a) disk status
# *                                     b) diskgroup state (mounted/dismounted)
# *                                     c) ASM alertlog for any ORA- errors occured in last 24 hours
# *                                     d) diskgroup used space;
# *                                        you can define warning/critical thresholds per diskgroup
# *
# * This plug-in needs to be run as ASM binaries owner (usually oracle).
# * Configure sudo to work with nrpe-owner.
# *
# * Run 'check_asm --help' for full description.
# *
# * Setup:
# *
# * 1. disable 'requiretty' for nrpe-owner in /etc/sudoers
# *    Defaults:nagios    !requiretty
# *
# * 2. enable sudo for nrpe-owner to run this script
# *    nagios          ALL=(oracle) NOPASSWD: /usr/lib64/nagios/plugins/check_asm
# *
# * 3. edit nrpe.cfg and insert required checks with options:
# *
# *    command[check_asm_diskstatus]=sudo -u oracle /usr/lib64/nagios/plugins/check_asm --asm_home=$ASM_HOME--action=diskstatus
# *    command[check_asm_dgstate]=sudo -u oracle /usr/lib64/nagios/plugins/check_asm --asm_home=$ASM_HOME- --action=dgstate
# *    command[check_asm_alertlogerror]=sudo -u oracle /usr/lib64/nagios/plugins/check_asm --asm_home=$ASM_HOME- --action=alertlogerror
# *    command[check_asm_usedspace]=sudo -u oracle /usr/lib64/nagios/plugins/check_asm --asm_home=$ASM_HOME- --action=usedspace --threshold DG1=98:99
# *
# * Sample output:
# *
# * check_asm --asm_home=/oracle/gridhome --action=diskstatus
# * [OK] Disk status: OK
# * check_asm --asm_home=/oracle/gridhome  --action=dgstate
# * [OK] Diskgroup state: (CRS: MOUNTED) (FRA: MOUNTED) (DATA: MOUNTED)
# * check_asm --asm_home=/oracle/gridhome  --action=alertlogerror
# * [OK] ASM AlertLog Errors: 0
# * check_asm --asm_home=/oracle/gridhome  --action=usedspace  --threshold DATA=95:98
# * [OK] Diskgroup used space: (CRS: 7.94%: OK) (FRA: 1.80%: OK) (DATA: 55.82%: OK)
# *
# *******************************************************************************

use Getopt::Long qw(:config no_ignore_case);

my ($sid, $asm_home, $action, $line, $used_space, $rounded_used_space, $warnPerc, $critPerc, $diskstatus, $diskname);
my ($adrbase, $adrhome, $numerrors, $output);

my %disk_groups_thresholds = ();
my ($defWarnPerc, $defCritPerc) = (85, 95);
my %nagios_exit_codes = ( 'UNKNOWN', 3, 'OK', 0, 'WARNING', 1, 'CRITICAL', 2 );
my $output_msg = '';
my $status = 'OK';
my $action = '';
my $help = '';

&usage unless GetOptions ('help' => \$help, 'asm_home=s' => \$asm_home, 'action=s' => \$action, 'threshold=s' => \%disk_groups_thresholds);

usage() if $help;

$sid = qx[ps -eaf | grep asm_smon | grep -v grep];
chomp $sid;
$sid =~ s/.+asm_smon_(\W+)/$1/;

if( $sid  !~ m/ASM/ ) {
  print "[<b>ASM instance is down!<\/b>]\n";
  exit $nagios_exit_codes{'CRITICAL'};
}

$ENV{ORACLE_SID} = $sid;
$ENV{ORACLE_HOME} = $asm_home;
delete $ENV{TWO_TASK};

if( $action eq 'status' ){
  $output_msg = "ASM instance is up";
}
elsif( $action eq 'dgstate' ) {

  $output_msg = "Diskgroup state: ";
  $output = qx[${asm_home}/bin/sqlplus -s \/ as sysdba <<!
set heading off echo off feed off linesize 80 pagesize 0
col name for a30
col state for a11
select STATE, name from v\\\$asm_diskgroup;
!
];
  $output =~ s/^\s*\n//gs;

  foreach $line (split /\n/, $output) {
    ($dgstate, $dgname) = split /\s+/, $line;
    $dgname =~ s/\W+//;
    $output_msg .= "($dgname: $dgstate) ";
    $status = 'CRITICAL' if $dgstate ne 'MOUNTED';
  }
}
elsif( $action eq 'usedspace' ) {

  $output_msg = "Diskgroup used space: ";
  $perfdata = "";
  $output = qx[${asm_home}/bin/sqlplus -s \/ as sysdba <<!
set heading off echo off feed off linesize 100 pagesize 0
col state for a12
col NAME for a30
select state, TOTAL_MB, USABLE_FILE_MB, NAME from v\\\$asm_diskgroup;
!
];
  $output =~ s/^\s*\n//gs;

  foreach $line (split /\n/, $output) {
    ($dgstate, $totalmb, $freemb, $dgname) = split /\s+/, $line;
    $dgname =~ s/\W+//;
    if( $dgstate eq 'MOUNTED' ) {
      $used_space = ( ($totalmb-$freemb) / $totalmb ) * 100;
      $rounded_used_space = sprintf("%.2f", $used_space);
      ($warnPerc, $critPerc) = ($defWarnPerc, $defCritPerc);
      ($warnPerc, $critPerc) = split /:/, $disk_groups_thresholds{$dgname} if exists  $disk_groups_thresholds{$dgname};

      if ( $rounded_used_space >= $warnPerc && $rounded_used_space < $critPerc ) {
        $status = 'WARNING' if $status eq 'OK';
        $output_msg .= "($dgname: $rounded_used_space%: WARNING) ";
      } elsif ( $rounded_used_space >= $critPerc ) {
        $status = 'CRITICAL';
        $output_msg .= "($dgname: $rounded_used_space%: CRITICAL) ";
      } else {
        $output_msg .= "($dgname: $rounded_used_space%: OK) ";
      }
      $perfdata .= " $dgname=$rounded_used_space%;$warnPerc;$critPerc";
    } else {
      $output_msg .= "($dgname: $dgstate) ";
    }

    # Once processed, we drop command line disk group and threshold
    delete($disk_groups_thresholds{$dgname});
  }
  $output_msg .= "| $perfdata";
}
elsif( $action eq 'diskstatus' ) {

  $output_msg = "Disk status: ";
  $output = qx[${asm_home}/bin/sqlplus -s \/ as sysdba <<!
set heading off echo off feed off linesize 170 pagesize 0
col mode_status for a10
col path for a150
select mode_status, path from v\\\$asm_disk;
!
];

  $output =~ s/^\s*\n//gs;

  foreach $line (split /\n/, $output) {
    ($diskstatus, $diskname) = split /\s+/, $line;
    $output_msg .= "($diskname - $diskstatus) ";
	
    $status = 'CRITICAL' if $diskstatus ne 'ONLINE';
  }
}
elsif( $action eq 'alertlogerror' ) {

  $numerrors = qx[${asm_home}/bin/sqlplus -s \/ as sysdba <<!
set heading off echo off feed off linesize 70 pagesize 0
select count(*) from X\\\$DBGALERTEXT where ORIGINATING_TIMESTAMP > systimestamp-1 and message_text like '%ORA-%';
!
];
  chomp $numerrors;
  $numerrors =~ s/\s+//gs;

  $status = 'WARNING' if $numerrors != 0;
  $output_msg = "ASM AlertLog Errors: $numerrors";
}
else {
  $status = 'CRITICAL';
  $output_msg = "[<blink><b>Unknown action name provided<\/b><\/blink>]";
}

# Let's check if any disk group remains in command line, not being present in ASM
if ( scalar keys %disk_groups_thresholds ) {
  $status = 'CRITICAL';
  foreach ( keys(%disk_groups_thresholds) ) {
    $output_msg = "[<blink><b>Diskgroup $_ is not present in $sid<\/b><\/blink>] ";
  }
}

print "[${status}] $output_msg\n";
exit $nagios_exit_codes{ $status };


########################## SUBROUTINES #######################

sub usage {
   print qq[
Usage: $0 --help --asm_home <ORACLE_HOME for ASM> --action <ACTION> --threshold <GROUP_DISK=integer> [[--threshold <GROUP_DISK=integer>] ... ]

--help:         prints this info
--asm_home:     ORACLE_HOME for asm instance
--action:       status|dgstate|diskstatus|usedspace|alertlogerror
--threshold:    GROUP_DISK_NAME=WarnPerc:CritPerc - percentage threshold for used space (range [0..100]) - use for <usedspace> action

];
   exit $nagios_exit_codes{'WARNING'};
}

