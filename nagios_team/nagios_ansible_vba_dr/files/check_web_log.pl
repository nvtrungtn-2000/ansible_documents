#!/usr/bin/perl
use File::ReadBackwards; # EPEL RPM: perl-File-ReadBackwards.noarch 
use Getopt::Long;
use Time::Piece; # RHEL package: perl-Time-Piece
use File::Find;


$time_pattern = '%Y-%m-%d %H:%M:%S';
$time_position = 0;
$totaltime = 0;
$maxtime_threshold = 15000;
$result = GetOptions (
            "pattern=s" => \$pattern, # string "Mẫu log request từ client"
			"pattern2=s" => \$pattern2, # string "Mẫu log response cho client"
			"pattern3=s" => \$pattern3, # string "Mẫu log lỗi"
            "logfile=s" => \$logfile, # string "đường dẫn file log của web app" 
            "interval=i" => \$interval, # int "thời gian check log"
			"warn=i" => \$warn, # int ""
			"crit=i" => \$crit, # int e.g. 30
			"max=i" => \$maxtime_threshold, # int e.g. 30
            "timepattern=s" => \$time_pattern, #string e.g. '%Y-%m-%d %H:%M:%S'
			"timeposition=i" => \$time_position, # int, each line is split into string on the space character, this provides the index of the first string block for the time
			"debug|d|vv" => \$debug, # flag/boolean
			"verbose|v" => \$verbose # flag/boolean
            ); 

my $now = localtime;

$oldestDate = $now - $interval*60;
if ($debug) { print "Now: $now and tzoffset: ". ($now)->tzoffset ."\n"; }
if ($debug) { print "Oldest date: $oldestDate and tzoffset: ". ($oldestDate)->tzoffset ."\n"; }


$hits = 0; # number of matches for the regex within the log files will be counted in this variable
$hits2 = 0;
$hits3 = 0;
$hits_maxtime =0;
$msg ="";
$validFileNames = 0; # number of files that match the given filename
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
	if ($File::Find::name =~ m/$logfile/ && (-T)) { # match only files that are ASCII files (-T) and that contain the file name
		$validFileNames += 1;	
		if ($debug) {  print "Found: $File::Find::name has age " .((-M)*1440-(360)) ." (minutes) \n"; }

		# -M returns the last change date of the file in fraction of days. e.g. 24 ago -> 1, 6 hours ago -> 0.25
		if ((-M)*1440-(360) < $interval) 
		{  # match only files whose last change (-M) is within the change interval
										# perldoc defines -M : Script start time minus file modification time, in days.

		$LOGS = File::ReadBackwards->new($File::Find::name) or
			die "Can't read file: $File::Find::name\n";

		while (defined($line = $LOGS->readline) ) {
			my @fields = split ' ', $line; # split the line into an array, split on ' '(space)
			$dateString = ""; # reset the datestring for each line
			for ($i=0; $i <= $dateFieldsCount; $i++) {
				$dateString .= $fields[$time_position + $i] . " "; # concatenate all date strings into one parseable string
			}
			$dateString =~ s/^\s+|\s+$//g ; # remove both leading and tailing whitespace - perl 6 will have a trim() function, until then - regex !
			$dateString =~ s/<|>|\]|\[//g ; # remove brackets
			$dateString =~ s/,\d+$|\.\d+$//g;


			if ($debug) { print "Datestring: $dateString \n";} # this is only needed if you are unsure which strings of the array are part of your datestring
			eval{
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

			if ($dt_tzadjusted > $oldestDate) { # is the date bigger=>newer than the oldest date we want to look at?
				if ($line =~ m/$pattern/){ # if the line contains the regex pattern
					if ($debug) {print $dt . " => ".$line; }
					if ($verbose) { print $line; }
					$hits++; # increase by 1 hit
				}
				if ($line =~ m/$pattern2/){ # if the line contains the regex pattern					
					$totaltime=($1+0)/1000+$totaltime;
					if ($debug) {print "ProcessTime =>".$totaltime; }
					if ($debug) {print $dt . " => ".$line; }
					if ($verbose) { print $line; }					
					$hits2++; # increase by 1 hit
				}
				if ($line =~ m/$pattern3/){ # if the line contains the regex pattern
					if ($debug) {print $dt . " => ".$line; }
					if ($verbose) { print $line; }
					$hits3++; # increase by 1 hit
				}
			}
			else{
				last; #if the date is older than the oldest we still care about, leave this loop -> go to the next file if available
			}
		} or next;
		}
		close(LOGS);
		}
	}
}## the find sub process ends here

if ($validFileNames == 0) {
	print "There were no files matching the passed filename: \"$logfile\"\n";
	exit 3; }
else {
	if ($hits+ $hits2 == 0){
		print "Not have any Request in last ".$interval." minutes|Request=".$hits;
		print ";0;0;0;0; Response=$hits2;0;0;0;0; AvgProcessTime=0;$maxtime_threshold;0;0;0; RequestNonSecurity=$hits3;$warn;$crit;0;0;\n";
		exit 2;
	}
	if ($hits3 >= $crit){
		print "Has ".$hits3." Request Non Security in last ".$interval." minutes".$interval." last minutes|Request=".$hits;
		print ";0;0;0;0; Response=$hits2;0;0;0;0; AvgProcessTime=".($totaltime/$hits2).";$maxtime_threshold;0;0;0; RequestNonSecurity=$hits3;$warn;$crit;0;0;\n";
		exit 2;
	}
	if (($totaltime/$hits2) >= $maxtime_threshold){
		print "Response is very slow,Avg ProcessTime=".($totaltime/$hits2)."ms in last ".$interval." minutes|Request=".$hits;
		print ";0;0;0;0; Response=$hits2;0;0;0;0; AvgProcessTime=".($totaltime/$hits2).";$maxtime_threshold;0;0;0; RequestNonSecurity=$hits3;$warn;$crit;0;0;\n";
		exit 1;
	}
		print "Has ".$hits."/".$hits2." Request/Response in last ".$interval." minutes|Request=".$hits;
		print ";0;0;0;0; Response=$hits2;0;0;0;0; AvgProcessTime=".($totaltime/$hits2).";$maxtime_threshold;0;0;0; RequestNonSecurity=$hits3;$warn;$crit;0;0;\n";
		exit 0;
}