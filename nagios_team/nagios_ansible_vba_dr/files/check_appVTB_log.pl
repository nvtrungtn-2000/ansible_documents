#!/usr/bin/perl
use File::ReadBackwards; # EPEL RPM: perl-File-ReadBackwards.noarch 
use Getopt::Long;
use Time::Piece; # RHEL package: perl-Time-Piece
use Time::Seconds;
use File::Find;

#use strict;


my $time_pattern = '%Y-%m-%dT%H:%M:%S'; #2016-11-10T18:41:49,648
my $warning = 5;
my $critical = 1;
my $no_transaction =1;
my $timeout_trans = 180; #giay
my $time_position = 0;
my $time_start = 8;
my $time_end = 22;
my $time_trans;
my $time_trans_max = 0;
my $time_trans_min = 200;
my $time_trans_avg = 0;
my $time_trans_total = 0;
my $num_trans = 0;
my $interval = 1;

			$pattern = 'response2Client:.*\\\"code\\\":\\\"00\\\"';#response2Client:.*\"code\":\"00\"
			$pattern2 = 'response2Client:.*\\\"code\\\":\\\"(151|100)\\\"';
			$pattern3 = 'Exception|timeout';
			$pattern_vcb ='(.*)\s-\s\[\d+\]\s-\s\[process\]\s-\s+INFO\sBusinessManager:\d+\s-\srequestTime:\s(\d+)'; 
			#2020-07-16T11:35:26,126 - [15948741260895] - [process] -  INFO BusinessManager:180 - requestTime: 36


$result = GetOptions (
            "logfile=s" => \$logfile, # string e.g. "/var/log/messages" 
            "interval=i" => \$interval, # int e.g. 30 for half an hour
            "timepattern=s" => \$time_pattern, #string e.g. '%Y-%m-%d %H:%M:%S'
			"timeposition=i" => \$time_position, # int, each line is split into string on the space character, this provides the index of the first string block for the time
            "warning|w=i" => \$warning, # int e.g. 3
			"critical|c=i" => \$critical, # int e.g. 5
			"timeout_trans|t=i" => \$timeout_trans, # timeout trans
			"time_start=i" => \$time_start, # int
			"time_end=i" => \$time_end, # int
			"no_transaction=i" => \$no_transaction, # int
			"debug|d|vv" => \$debug, # flag/boolean
			"verbose|v" => \$verbose, # flag/boolean
            ); 
            

############

sub get_ms {
        my ($ts,$ms) = split /,/ => shift;
        Time::Piece->strptime($ts, $time_pattern)->epoch*1000+$ms;
    }
#############


my $now = localtime;
$oldestDate = $now - $interval*60;
if ($debug) { print "Now: $now and tzoffset: ". ($now)->tzoffset ."\n"; }
if ($debug) { print "Oldest date: $oldestDate and tzoffset: ". ($oldestDate)->tzoffset ."\n"; }


my $hits = 0; # number of matches for the regex within the log files will be counted in this variable
my $hits2 = 0;
my $hits3 = 0;
my $hits_time = 0;
my $msg ="";
my $line_no = 0;
my $validFileNames = 0; # number of files that match the given filename
my @dateFields = $time_pattern =~ / /g; #  how many spaces do we have in our time pattern?
my $dateFieldsCount = @dateFields; # count the number spaces in the date format

if ($debug) { 
$verbose = 1; # if we debug, we want to have all information
print "Interval: $interval equals " . ($interval/1440) . " Fraction of days.\n";
}


$logfile=~m/^.+\//; 
$DIR=$&; # greedy matching from theline above

@files = find(\&process, $DIR);
sub process {
### note the following is done for each file that is found and matches the name and date criteria
	if ($File::Find::name =~ m/$logfile$/ ) { # && (-T) match only files that are ASCII files (-T) and that contain the file name
		$validFileNames += 1;	
		if ($debug) {  print "Found: $File::Find::name has age " .((-M)*1440-(360)) ." (minutes) \n"; }

		# -M returns the last change date of the file in fraction of days. e.g. 24 ago -> 1, 6 hours ago -> 0.25
		if ((-M)*1440-(360) < $interval+$timeout_trans) 
			{  # match only files whose last change (-M) is within the change interval
											# perldoc defines -M : Script start time minus file modification time, in days.

			$LOGS = File::ReadBackwards->new($File::Find::name) or
				die "Can't read file: $File::Find::name\n";

			while (defined($line = $LOGS->readline) ) {
				$line_no++;
			#if ($debug) {print $line."/n"; }
				my @fields = split ' ', $line; # split the line into an array, split on ' '(space)
				$dateString = ""; # reset the datestring for each line
				for ($i=0; $i <= $dateFieldsCount; $i++) {
					$dateString .= $fields[$time_position + $i] . " "; # concatenate all date strings into one parseable string
				}
				$dateString =~ s/^\s+|\s+$//g ; # remove both leading and tailing whitespace - perl 6 will have a trim() function, until then - regex !
				$dateString =~ s/<|>|\]|\[//g ; # remove brackets
				$dateString =~ s/,\d+$|\.\d+$//g;
                if ($dateString ==""){next;}

				#if ($debug) { print "Datestring: $dateString \n";} # this is only needed if you are unsure which strings of the array are part of your datestring
				
				eval
				{
					my $dt =  Time::Piece->strptime($dateString, $time_pattern); # parse string into Time::Piece object
					my $dt_tzadjusted = ($dt - $now->tzoffset); # TIME::PIECE assumes the parsed dates will be UTC, we need to adjust to the local tz offset
					
					# some date formats don't have the year information e.g. Dec 31 15:50:57 -> the year would automatically be parsed to 1970, 
					# which is probably never correct. We will correct this to this or last year
					if ($dt->year eq 1970) { 
						$dt = $dt->add_years($now->year - 1970); # We cannot set the year directly. So we add the number of years that have passed since 1970. 
						$dt_tzadjusted = ($dt - $now->tzoffset);
						# NOTE: If $now is January 1st and we're looking at log files from the end of last year, we will add too many years
						# hence if the date is now in the future, we subtract one year again.
						if ($dt_tzadjusted > $now) { 
							$dt = $dt->add_years(-1);
							$dt_tzadjusted = ($dt - $now->tzoffset);
						}
					}
					
					
					if ($dt_tzadjusted > ($oldestDate)) { #Khoang thoi gian tim End
						#if ($debug) {print "$line_no => ".$line; }
						if ($line =~ m/$pattern_vcb/){
							#if ($debug) {print " => Time Trans: $time_trans \n"; }
							$time_trans = ($2+0)/1000;
							if ($time_trans > 20){ 
							$hits_time++;
							$msg .= $line ;}
							#Tinh min max
							if ($time_trans > $time_trans_max) {$time_trans_max = $time_trans;}
							if ($time_trans < $time_trans_min) {$time_trans_min = $time_trans;}		
							$num_trans++;
							}
						if ($line =~ m/$pattern/){ # if the line contains the regex pattern
							$hits++; # increase by 1 hit
							#if ($debug) {print " => Hit pattern: $pattern \n"; }
						}
						if ($line =~ m/$pattern2/){ # if the line contains the regex pattern
														
							$hits2++; # increase by 1 hit
							$msg = $line;
						}
						if ($line =~ m/$pattern3/){ # if the line contains the regex pattern
							$hits3++; # increase by 1 hit
							$msg = $line;
						}
					}else{
					#if ($debug) {print "/n--------------:".$dt_tzadjusted . " => ".($oldestDate - $timeout_trans)."/n"; }
					#if ($debug) {print $line."/n"; }
						last; #if the date is older than the oldest we still care about, leave this loop -> go to the next file if available
					}
				} or next;
			}close(LOGS);
		}
	}
}## the find sub process ends here

# if ($num_trans>0) {$time_trans_avg = $time_trans_total / $num_trans;} # Tinh AVG
# else {$time_trans_min=0;}

if ($validFileNames == 0) {
	print "Khong tim thay file: \"$logfile\"";
	exit 2; 
}	
if ($hits3 > ($critical + 0)) {
	print "Co $hits3 giao dich timeout va ".$hits."/".($hits2+$hits3)." giao dich Successed/Failed trong $interval phut vua qua\n$msg";
	print "|Trans_successed=".$hits;
	print ";0;0;0;0; Trans_failed=".($hits2+$hits3);
	print ";$warning;$critical;0;0; ";
	print "Trans_time=".$hits_time;
	printf " Trans_time_max=%.1fs",$time_trans_max;
	print "\n";
	exit 2; 
} 
if ($hits2 >= ($warning + 0) || ($hits==0 && $hits2 > 0)) {
	print "Co ".$hits."/".($hits2+$hits3)." giao dich Successed/Failed trong $interval phut vua qua";;
	print "|Trans_successed=".$hits;
	print ";0;0;0;0; Trans_failed=".($hits2+$hits3);
	print ";$warning;$critical;0;0; ";
	print "Trans_time=".$hits_time;
	printf " Trans_time_max=%.1fs",$time_trans_max;
	print "\n";
	exit 1; 
}	
if ($hits_time > 3){
printf "Co ".$hits_time." giao dịch cham vuot nguong 20s.\n$msg";
print "|Trans_successed=".$hits;
print ";0;0;0;0; Trans_failed=".($hits2+$hits3);
print ";$warning;$critical;0;0; ";
print "Trans_time=".$hits_time;
printf " Trans_time_max=%.1fs",$time_trans_max;
print "\n";
exit 1;
}
	
if (($no_transaction+0 == 1) && ($hits+$hits2 == 0) &&($now->hour >= $time_start)&& ($now->hour <= $time_end)) {
	print "Khong co giao dich nao trong $interval phut vua qua";
	print "|Trans_successed=".$hits;
	print ";0;0;0;0; Trans_failed=".($hits2+$hits3);
	print ";$warning;$critical;0;0; ";
	print "Trans_time=".$hits_time;
	printf " Trans_time_max=%.1fs",$time_trans_max;
	print "\n";
	exit 1; 
}

print "Co ".$hits."/".($hits2+$hits3)." giao dich Successed/Failed trong ".$interval." phut qua|Trans_successed=".$hits;
print ";0;0;0;0; Trans_failed=".($hits2+$hits3);
print ";$warning;$critical;0;0; ";
print "Trans_time=".$hits_time;
printf " Trans_time_max=%.1fs",$time_trans_max;
print "\n";
exit 0;

