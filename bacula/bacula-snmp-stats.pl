#!/usr/bin/perl -w

# {{{ $Id: bacula-snmp-stats.pl,v 1.6 2005-10-05 17:35:30 turbo Exp $
#
# Extract job statistics for a bacula backup server.
# Only tested with a MySQL backend, but is general
# enough to work with the PostgreSQL backend as well.
#
# Uses the perl module DBI for database access.
# Require the file "/etc/bacula/.conn_details"
# with the following defines:
#
#	USERNAME=
#	PASSWORD=
#	DB=
#	HOST=
#	CATALOG=
#
# Since using perl DBI, 'CATALOG' can be any database
# backend that's supported by the module (currently
# Bacula only supports MySQL and PostgreSQL though).
#
# Copyright 2005 Turbo Fredriksson <turbo@bayour.com>.
# This software is distributed under GPL v2.
# }}}

# {{{ Include libraries and setup global variables
# Forces a buffer flush after every print
$|=1;

use strict; 
use DBI;
use POSIX qw(strftime);

$ENV{PATH}   = "/bin:/usr/bin:/usr/sbin";
my $OID_BASE = ".1.3.6.1.4.1.8767.2.3"; # .iso.org.dod.internet.private.enterprises.bayourcom.snmp.baculastats
my $DEBUG = 0;

my %keys = ("5" => "start_date",
	    "6" => "end_date",
	    "7" => "duration",
	    "8" => "files",
	    "9" => "bytes");

my %function_print = ("1" => "clients_index",
		      "2" => "clients_name",
		      "3" => "jobs_name",
		      "4" => "jobs_id",
		      "5" => "jobs_status",
		      "6" => "jobs_status",
		      "7" => "jobs_status",
		      "8" => "jobs_status",
		      "9" => "jobs_status");

# Some global data variables
my($oid, $nr, @Jobs, %JOBS, %STATUS, %Status, @CLIENTS);

# Because &print_jobs_name() needs TWO args, not ONE,
# but &call_func() can't handle that and it would be
# cumbersome to make it do that...
# The function &print_jobs_name() needs: 'Client number'
# and 'Job number' but we set the client number as a global
# variable, and send it (the function) the value of the
# job number.
my($CLIENT_NO);

# Same as above, but for the job number in print_jobs_name().
my($JOB_NO);

# Same as above, but for the job ID in print_jobs_id().
my($JOB_ID);

# This is for the print_jobs_status() function to know
# which type of status wanted (from %keys above).
my($STATUS_TYPE);

# handle a SIGALRM - read information from the SQL server
$SIG{'ALRM'} = \&load_information;
# }}}

# {{{ OID Tree definition
#	OID_BASE.1.0		totals			Total number of backup clients		&print_clients_amount()
#	OID_BASE.2.1.1.x.y	clientIndex							&print_clients_index()
#	OID_BASE.2.1.2.x.y	client			Client name				&print_clients_name()
#	OID_BASE.2.1.3.x.y	job			Job name				&print_jobs_name()
#	OID_BASE.2.1.4.x.y	client.job		Job ID					&print_jobs_id()
#	OID_BASE.2.1.5.x.y	client.job.date		Date of job start: YYYY-MM-DD HH:MM:SS	&print_jobs_status()
#	OID_BASE.2.1.6.x.y	client.job.date		Date of job end:   YYYY-MM-DD HH:MM:SS	&print_jobs_status()
#	OID_BASE.2.1.7.x.y	client.job.time		Time the job took (in seconds)		&print_jobs_status()
#	OID_BASE.2.1.8.x.y	client.job.files	Files backed up in the job		&print_jobs_status()
#	OID_BASE.2.1.9.x.y	client.job.bytes	Bytes backed up in the job		&print_jobs_status()
# }}}

# {{{ Tests
#	root@aurora:~# bacula-snmp-stats.pl --debug --all | egrep '\.2\.1\.3\.1\.6 |\.2\.1\.[4-9]\.1\.6\.1 '
#	OID_BASE.2.1.3.1.6 Backup_Homes
#	OID_BASE.2.1.4.1.6.1 Backup_Homes.2005-09-09_01.05.08
#	OID_BASE.2.1.5.1.6.1 2005-09-17 08:28:52
#	OID_BASE.2.1.6.1.6.1 2005-09-17 09:29:32
#	OID_BASE.2.1.7.1.6.1 3640
#	OID_BASE.2.1.8.1.6.1 681
#	OID_BASE.2.1.9.1.6.1 306488911
#
#	root@aurora:~# bacula-snmp-stats.pl -d -g OID_BASE.2.1.4.1.6.1
#	OID_BASE.2.1.4.1.1.1 Aurora_System.2005-09-10_03.00.00
#
#	root@aurora:~# bacula-snmp-stats.pl -d -n OID_BASE.2.1.4.1.6.1
#	OID_BASE.2.1.4.1.1.2 Aurora_System.2005-09-11_03.00.01
# }}}


# ====================================================
# =====    R E T R E I V E  F U N C T I O N S    =====

# {{{ Load the information needed to connect to the MySQL server.
my %CFG;
sub get_config {
    my($line, $key, $value);

    if(-e "/etc/bacula/.conn_details") {
	open(CFG, "< /etc/bacula/.conn_details") || die("Can't open /etc/bacula/.conn_details, $!");
	while(!eof(CFG)) {
	    $line = <CFG>; chomp($line);
	    ($key, $value) = split('=', $line);
	    $CFG{$key} = $value;
	}
	close(CFG);
    }
}
# }}}

# {{{ Open a connection to the SQL database.
my $dbh = 0;
sub sql_connect {
    my $connect_string = "dbi:$CFG{'CATALOG'}:database=$CFG{'DB'}:host=$CFG{'HOST'}";

    my $user = $CFG{'USERNAME'} if(defined($CFG{'USERNAME'}));
    my $pass = $CFG{'PASSWORD'} if(defined($CFG{'PASSWORD'}));

    # Open up the database connection...
    $dbh = DBI->connect($connect_string, $user, $pass);
    if(!$dbh) {
        printf(STDERR "Can't connect to $CFG{'CATALOG'} database $CFG{'DB'} at $CFG{'HOST'}.\n" );

	exit 1 if($DEBUG);
    }
}
# }}}

# {{{ Get number of clients
sub get_clients_amount {
    my $sth = $dbh->prepare("SELECT COUNT(*) FROM Client") || die("Could not prepare SQL query: $dbh->errstr\n");
    $sth->execute || die("Could not execute query: $sth->errstr\n");
    return($sth->fetchrow_array());
}
# }}}

# {{{ Get client names
sub get_clients {
    my $client = shift;
    my @clients;

    # Make sure the first (number '0') of the array is empty,
    # so we can start the OID's at '1'.
    push(@clients, '');

    my $sth = $dbh->prepare("SELECT ClientId,Name FROM Client WHERE Name LIKE '$client' ORDER BY ClientID")
	|| die("Could not prepare SQL query: $dbh->errstr\n");
    $sth->execute || die("Could not execute query: $sth->errstr\n");
    while( my @row = $sth->fetchrow_array() ) {
	my $nr = $row[0];
	push(@clients,  $row[0].";".$row[1]);
    }

    return(@clients);
}
# }}}

# {{{ Get job names
sub get_jobs {
    my $client = shift;
    my $job = shift;
    my($QUERY, $line, %jobs, @jobs);

    $QUERY  = "SELECT Name FROM Job WHERE ClientId=$client AND JobErrors=0 ";
    $QUERY .= "AND Name LIKE '$job' ORDER BY Name";

    my $sth = $dbh->prepare($QUERY) || die("Could not prepare SQL query: $dbh->errstr\n");
    $sth->execute || die("Could not execute query: $sth->errstr\n");
    while( my @row = $sth->fetchrow_array() ) {
	$jobs{$row[0]} = $line if(!$jobs{$row[0]});
    }

    foreach my $job (sort keys %jobs) {
	push(@jobs, $job);
    }

    return(@jobs);
}
# }}}

# {{{ Get status for this job and this client
sub get_status {
    my $client = shift;
    my $job = shift;
    my($QUERY, $line, %status);

    $QUERY  = "SELECT Job,StartTime,EndTime,JobFiles,JobBytes FROM Job WHERE ";
    $QUERY .= "ClientId=$client AND JobErrors=0 AND Name LIKE '$job' ORDER BY Job";

    my $sth = $dbh->prepare($QUERY) || die("Could not prepare SQL query: $dbh->errstr\n");
    $sth->execute || die("Could not execute query: $sth->errstr\n");
    while( my @row = $sth->fetchrow_array() ) {
	# 0: 'Aurora_System.2005-09-15_03.00.01'
	# 1: '2005-09-15 07:56:30'
	# 2: '2005-09-15 10:16:58'
	# 3: '97646'			MIGHT BE EMPTY
	# 4: '2749710101'		MIGHT BE EMPTY

	my ($start_date, $start_time) = split(' ', $row[1]);
	my ($end_date,   $end_time)   = split(' ', $row[2]);
	$row[3] = 0 if(!$row[3]);
	$row[4] = 0 if(!$row[4]);

#	print "Status (",$row[0],"): $start_date;$start_time;$end_date;$end_time;",$row[3].";",$row[4],"\n";
	$status{$row[0]}  = "$start_date;$start_time;$end_date;$end_time;".$row[3].";".$row[4];
    }

    return(%status);
}
# }}}


# ====================================================
# =====       P R I N T  F U N C T I O N S       =====

# {{{ Output total number of clients.
sub print_clients_amount {
    if($DEBUG) {
	&echo(0, "=> OID_BASE.totals.0\n") if($DEBUG > 1);
	&echo(0, "$OID_BASE.1.0 $nr\n");
    }

    &echo(1, "$OID_BASE.1.0\n");
    &echo(1, "integer\n");
    &echo(1, "$nr\n");

    return 1;
}
# }}}

# {{{ Output client index
sub print_clients_index {
    my $client_no = shift; # Client number
    my($i, $max);
    &echo(0, "=> OID_BASE.clientTable.clientEntry.IndexClients\n") if($DEBUG > 1);

    if(defined($client_no)) {
	# {{{ Specific client index
	if(!$CLIENTS[$client_no]) {
	    &echo(0, "=> No value in this object ($client_no)\n") if($DEBUG);
	    return 0;
	}
    
	$i = $client_no;

	# This SHOULD go just a tad faster. In theory any way.
	# Don't seem to be the case though. BUG!?
	#$max = $nr;
	$max = $client_no;
# }}}
    } else {
	# {{{ The FULL client index
	$i = 1;
	$max = $nr;
# }}}
    }

    # {{{ Output index
    for(; $i <= $max; $i++) {
	&echo(0, "$OID_BASE.2.1.1.$i $i\n") if($DEBUG);

	&echo(1, "$OID_BASE.2.1.1.$i\n");
	&echo(1, "integer\n");
	&echo(1, "$i\n");
    }
# }}}

    return 1;
}
# }}}

# {{{ Output client name
sub print_clients_name {
    my $client_no = shift; # Client number
    my($i, $max);
    &echo(0, "=> OID_BASE.clientTable.clientEntry.clientName\n") if($DEBUG > 1);

    if(defined($client_no)) {
	# {{{ Specific client name
	if(!$CLIENTS[$client_no]) {
	    &echo(0, "=> No value in this object\n") if($DEBUG);
	    return 0;
	}
    
	$i = $client_no;
	
	# This SHOULD go just a tad faster. In theory any way.
	# Don't seem to be the case though. BUG!?
	#$max = $nr;
	$max = $client_no;
# }}}
    } else {
	# {{{ ALL client names
	$i = 1;
	$max = $nr;
# }}}
    }

    # {{{ Output client names
    for(; $i <= $max; $i++) {
	next if(!$CLIENTS[$i]);
	my ($nr, $name) = split(';', $CLIENTS[$i]);
	
	&echo(0, "$OID_BASE.2.1.2.$nr $name\n") if($DEBUG);

	&echo(1, "$OID_BASE.2.1.2.$nr\n");
	&echo(1, "string\n");
	&echo(1, "$name\n");
    }
# }}}

    return 1;
}
# }}}

# {{{ Output job name
sub print_jobs_name {
    my $jobnr = shift; # Job number
    my $success = 0;
    &echo(0, "=> OID_BASE.clientTable.clientEntry.jobName\n") if($DEBUG > 1);

    if(defined($CLIENT_NO)) {
	# {{{ Specific client
	if(!$CLIENTS[$CLIENT_NO]) {
	    &echo(0, "=> No value in this object\n") if($DEBUG > 1);
	    return 0;
	}
    
	# Get client name from the client number.
	my ($client_no, $client_name) = split(';', $CLIENTS[$CLIENT_NO]);

	my $j=1;
	foreach my $job (sort keys %{ $JOBS{$client_name} }) {
	    if($j == $jobnr) {
		&echo(0, "$OID_BASE.2.1.3.$client_no.$j $job\n") if($DEBUG);

		&echo(1, "$OID_BASE.2.1.3.$client_no.$j\n");
		&echo(1, "string\n");
		&echo(1, "$job\n");

		$success = 1;
	    }
	    
	    $j++;
	}
# }}}
    } else {
	# {{{ ALL clients
	my $i=1;

	foreach my $client (@CLIENTS) {
	    next if(!$client);
	    my $client_name = (split(';', $client))[1];

	    my $j=1;
	    foreach my $job (sort keys %{ $JOBS{$client_name} }) {
		&echo(0, "$OID_BASE.2.1.3.$i.$j $job\n") if($DEBUG);

		&echo(1, "$OID_BASE.2.1.3.$i.$j\n");
		&echo(1, "string\n");
		&echo(1, "$job\n");
		
		$success = 1;
		$j++;
	    }
	    
	    $i++;
	}
# }}}
    }

    return $success;
}
# }}}

# {{{ Output job id
sub print_jobs_id {
    my $job_id_nr = shift; # Job number
    my $success = 0;
    &echo(0, "=> OID_BASE.clientTable.clientEntry.jobId\n") if($DEBUG > 1);

    if(defined($CLIENT_NO)) {
	# {{{ Specific clients job ID
	if(!$CLIENTS[$CLIENT_NO]) {
	    &echo(0, "=> No such client ID ($CLIENT_NO)\n") if($DEBUG > 1);

	    return 0;
	}

	# Get client name from the client number.
	my $client_name = (split(';', $CLIENTS[$CLIENT_NO]))[1];

	# OID_BASE.2.1.4.$CLIENT_NO
	my $j=1;
	foreach my $job_name (sort keys %{ $JOBS{$client_name} }) {
	    if($j == $JOB_NO) {
		# OID_BASE.2.1.4.$CLIENT_NO.$JOB_NO
                my $k=1;
                foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
		    if($k == $job_id_nr) {
			# OID_BASE.2.1.4.$CLIENT_NO.$JOB_NO.job_id_nr
			&echo(0, "$OID_BASE.2.1.4.$CLIENT_NO.$JOB_NO.$k $job_id\n") if($DEBUG);

			&echo(1, "$OID_BASE.2.1.4.$CLIENT_NO.$JOB_NO.$k\n");
			&echo(1, "string\n");
			&echo(1, "$job_id\n");

			$success = 1;
		    }
		    
                    $k++;
                }
	    }
	    
	    $j++;
	}
# }}}
    } else {
	# {{{ ALL clients job ID
	my $i=1;
	foreach my $client (@CLIENTS) {
	    next if(!$client);
	    my $client_name = (split(';', $client))[1];

	    my $j=1;
	    foreach my $job_name (sort keys %{ $JOBS{$client_name} }) {
		my $k=1;
		foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
		    &echo(0, "$OID_BASE.2.1.4.$i.$j.$k $job_id\n") if($DEBUG);

		    &echo(1, "$OID_BASE.2.1.4.$i.$j.$k\n");
		    &echo(1, "string\n");
		    &echo(1, "$job_id\n");
		    
		    $success = 1;
		    $k++;
		}
		
		$j++;
	    }
	    
	    $i++;
	}
# }}}
    }

    return $success;
}
# }}}

# {{{ Output job status
sub print_jobs_status {
    my $job_status_nr = shift;
    my $success = 0;

    if(defined($CLIENT_NO)) {
	# {{{ Status for a specific client, specific job ID and a specific type
	if(!$CLIENTS[$CLIENT_NO]) {
	    &echo(0, "=> No value in this object\n") if($DEBUG > 1);
	    return 0;
	}

	# Get client name from the client number (which is a global variable).
	my $client_name = (split(';', $CLIENTS[$CLIENT_NO]))[1];

	# Get the key name from the key number (which is a global variable).
	my $key_name = $keys{$STATUS_TYPE};

	# OID_BASE.2.1.$STATUS_TYPE.$CLIENT_NO
	my $i=1;
	foreach my $job_name (sort keys %{ $JOBS{$client_name} }) {
	    if($i == $JOB_NO) {
		# OID_BASE.2.1.$STATUS_TYPE.$CLIENT_NO.$JOB_NO
		
		my $j=1;
		foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
		    if($j == $job_status_nr) {
			# OID_BASE.2.1.$STATUS_TYPE.$CLIENT_NO.$JOB_NO
			if($DEBUG > 2) {
			    my $string = sprintf("=> %-s %-20s (%s)\n",
						 "$OID_BASE.clientTable.clientEntry.$key_name.$client_name.$job_name.$j ",
						 $STATUS{$client_name}{$job_name}{$job_id}{$key_name},
						 "$client_name->$job_name->$job_id");
			    &echo(0, $string);

			    &echo(0, "$OID_BASE.2.1.$STATUS_TYPE.$CLIENT_NO.$JOB_NO.$j ",$STATUS{$client_name}{$job_name}{$job_id}{$key_name},"\n");
			} elsif($DEBUG) {
			    &echo(0, "$OID_BASE.2.1.$STATUS_TYPE.$CLIENT_NO.$JOB_NO.$j ",$STATUS{$client_name}{$job_name}{$job_id}{$key_name},"\n");
			}

			&echo(1, "$OID_BASE.2.1.$STATUS_TYPE.$CLIENT_NO.$JOB_NO.$j\n");
			if(($key_name eq 'start_date') || ($key_name eq 'end_date')) {
			    &echo(1, "string\n");
			} else {
			    &echo(1, "integer\n");
			}
			&echo(1, $STATUS{$client_name}{$job_name}{$job_id}{$key_name}."\n");

			$success = 1;
		    }
		    
		    $j++;
		}
	    }
	    
	    $i++;
	}
# }}}
    } else {
	# {{{ ALL clients, all job status
	foreach my $key_nr (sort keys %keys) {
	    my $key_name = $keys{$key_nr};
	    
	    my $i=1; # Client ID
	    &echo(0, "=> OID_BASE.clientTable.clientEntry.$key_name.clientId.jobNr.cnt\n") if($DEBUG > 1);
	    foreach my $client (@CLIENTS) {
		next if(!$client);
		my $client_name = (split(';', $client))[1];
		
		my $j=1; # Job Name
		foreach my $job_name (keys %{ $JOBS{$client_name} }) {
		    my $k=1; # Job ID
		    foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
			if($DEBUG > 2) {
			    my $string = sprintf("%-25s %-20s %s\n",
						 "$OID_BASE.2.1.$key_nr.$i.$j.$k ",
						 $STATUS{$client_name}{$job_name}{$job_id}{$key_name},
						 "$client_name->$job_name->$job_id");
			    &echo(0, $string);
			} elsif($DEBUG) {
			    &echo(0, "$OID_BASE.2.1.$key_nr.$i.$j.$k ",$STATUS{$client_name}{$job_name}{$job_id}{$key_name},"\n");
			}

			&echo(1, "$OID_BASE.2.1.$key_nr.$i.$j.$k\n");
			if(($key_name eq 'start_date') || ($key_name eq 'end_date')) {
			    &echo(1, "string\n");
			} else {
			    &echo(1, "integer\n");
			}
			&echo(1, $STATUS{$client_name}{$job_name}{$job_id}{$key_name}."\n");
			
			$success = 1;
			$i++;
		    }
		    
		    $k++;
		}
		
		$j++;
	    }    
	}
# }}}
    }

    return $success;
}
# }}}


# ====================================================
# =====        M I S C  F U N C T I O N S        =====

# {{{ Show usage
sub help {
    my $name = `basename $0`; chomp($name);

    &echo(0, "Usage: $name [option] [oid]\n");
    &echo(0, "Options: --debug|-d	Run in debug mode\n");
    &echo(0, "         --all|-a	Get all information\n");
    &echo(0, "         -n		Get next OID ('oid' required)\n");
    &echo(0, "         -g		Get specified OID ('oid' required)\n");

    exit 1 if($DEBUG);
}
# }}}

# {{{ Calculate how long a job took
sub calculate_duration {
    my $start_date = shift;
    my $start_time = shift;
    my $end_date   = shift;
    my $end_time   = shift;

    if(($start_date eq "0000-00-00") || ($end_date eq "0000-00-00") ||
       ($start_time eq "00:00:00")   || ($end_time eq "00:00:00")) {
	return(-1);
    }

    my $unix_start = `date -d "$start_date $start_time" "+%s"`; chomp($unix_start);
    my $unix_end   = `date -d "$end_date $end_time" "+%s"`; chomp($unix_end);

    return($unix_end - $unix_start);
}
# }}}

# {{{ Call function with option
sub call_func {
    my $func_nr  = shift;
    my $func_arg = shift;

    my $func = "print_".$function_print{$func_nr};
    &echo(0, "=> Calling function '$func($func_arg)'\n") if($DEBUG > 1);

    $func = \&{$func}; # Because of 'use strict' above...
    &$func($func_arg);
}
# }}}

# {{{ Output some extra debugging
sub output_extra_debugging {
    my @tmp = @_;

    my $string = "=> ";
    for(my $i=0; defined($tmp[$i]); $i++) {
	$string .= "tmp[$i]=".$tmp[$i];
	$string .= ", " if(defined($tmp[$i+1]));
    }
    $string .= "\n";

    &echo(0, $string);
}
# }}} # Extra debugging

# {{{ Find the current date and time
# Returns a string something like: '10/8-96 16:27'
sub get_timestring {
    my($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime;

    return POSIX::strftime("20%y-%m-%d %H:%M:%S",
			    $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst);
}
# }}}

# {{{ Open logfile for debugging
sub open_log {
    if(!open(LOG, ">> /var/log/bacula-snmp-stats.log")) {
	&echo(0, "Can't open logfile '/var/log/bacula-snmp-stats.log', $!\n") if($DEBUG);
	return 0;
    } else {
	return 1;
    }
}
# }}}

# {{{ Log output
sub echo {
    my $stdout = shift;
    my $string = shift;
    my $log_opened = 0;

    # Open logfile if debugging OR running from snmpd.
    if($DEBUG || $ENV{'MIBDIRS'}) {
	if(&open_log()) {
	    $log_opened = 1;
	    open(STDERR, ">&LOG");
	}
    }

    print LOG &get_timestring()," $string" if($log_opened);
    print $string if($stdout);
}
# }}}

# {{{ Load all information needed
sub load_information {
    # {{{ How many base counters?
    my $keys_counters;
    foreach (keys %keys) {
	$keys_counters++;
    }
    # }}}

    # {{{ Load configuration file and connect to SQL server.
    &get_config();
    &sql_connect();
    # }}}

    # {{{ Get total number of clients.
    $nr = &get_clients_amount;
    # }}}

    # {{{ Get names of all clients.
    @CLIENTS = &get_clients("%");
    # }}}

    # {{{ Go through each client, retreiving it's job names.
    foreach my $client (@CLIENTS) {
	next if(!$client);
	my($client_nr, $client_name) = split(';', $client);
	
	# Get job name(s) for this client.
	@Jobs = &get_jobs($client_nr, '%');
	
	# Go through each job name of this client, getting
	# finished/executed jobs.
	my $job;
	foreach $job (@Jobs) {
	    $JOBS{$client_name}{$job} = $job;
	    
	    %Status = &get_status($client_nr, $job);
	    
	    my $id;
	    foreach $id (sort keys %Status) {
		my($start_date, $start_time, $end_date, $end_time, $files, $bytes)
		    = split(';', $Status{$id});
		
		my $duration = &calculate_duration($start_date, $start_time, $end_date, $end_time);

		my $start = $start_date." ".$start_time;
		$start =~ s/\-//g; $start =~ s/\ //g; $start =~ s/://g; $start .= "Z";

		my $end   = $end_date." ".$end_time;
		$end   =~ s/\-//g; $end   =~ s/\ //g; $end   =~ s/://g; $end   .= "Z";
		
		$STATUS{$client_name}{$job}{$id}{"start_date"} = $start;
		$STATUS{$client_name}{$job}{$id}{"end_date"}   = $end;
		$STATUS{$client_name}{$job}{$id}{"duration"}   = $duration;
		$STATUS{$client_name}{$job}{$id}{"files"}      = $files;
		$STATUS{$client_name}{$job}{$id}{"bytes"}      = $bytes;
	    }
	}
    }
    # }}}

    # Schedule an alarm once every hour to re-read information.
    alarm(60*60);
}
# }}}

# {{{ Stuff to do when we're done. ALWAYS (even if crash!).
sub END {
    # Disconnect from the database.
    $dbh->disconnect() if($dbh);
}
# }}}

# ====================================================
# =====          P R O C E S S  A R G S          =====

# Load information
&load_information();

# {{{ Go through the argument(s) passed to the program
my $ALL = 0;
for(my $i=0; $ARGV[$i]; $i++) {
    if($ARGV[$i] eq '--help' || $ARGV[$i] eq '-h' || $ARGV[$i] eq '?' ) {
	&help();
    } elsif($ARGV[$i] eq '--debug' || $ARGV[$i] eq '-d') {
	$DEBUG++;
    } elsif($ARGV[$i] eq '--all' || $ARGV[$i] eq '-a') {
	$ALL = 1;
    }
}
# }}}

if($ALL) {
    # {{{ Output the whole MIB tree - used mainly/only for debugging purposes.
    # Output total number of clients.
    &print_clients_amount();
    
    # Output the 'clientIndex'.
    &print_clients_index();
    
    # Output each client name
    &print_clients_name();
    
    # Output each job name
    &print_jobs_name();
    
    # Output each job id
    &print_jobs_id();
    
    # Output each jobs status
    &print_jobs_status();
# }}}
} else {
    # {{{ Go through the commands sent on STDIN
    while(<>) {
	if (m!^PING!){
	    print "PONG\n";
	    next;
	}

	# {{{ Get all run arguments - next/specfic OID
	my $arg = $_; chomp($arg);
	&echo(0, "=> ARG=$arg\n") if($DEBUG > 1);
	
	# Get next line from STDIN -> OID number.
	# $arg == 'getnext' => Get next OID
	# $arg == 'get' (?) => Get specified OID
	$oid = <>; chomp($oid);
	$oid =~ s/$OID_BASE//; # Remove the OID base
	$oid =~ s/^\.//;       # Remove the first dot if it exists - it's in the way!
	&echo(0, "=> OID=$oid\n") if($DEBUG > 1);
	
	my @tmp = split('\.', $oid);
	&output_extra_debugging(@tmp) if($DEBUG > 1);
# }}}
	
	if(!defined($tmp[0])) {
	    # {{{ ------------------------------------- OID_BASE   
	    &print_clients_amount();
# }}} # OID_BASE
	} elsif($tmp[0] == 1) {
	    # {{{ ------------------------------------- OID_BASE.1 
	    if($arg eq 'getnext') {
		if(!defined($tmp[1])) {
		    # OID_BASE.1
		    &print_clients_amount();
		} else {
		    # OID_BASE.1.x
		    &print_clients_index(1);
		}
	    } else {
		if(!defined($tmp[1])) {
		    &echo(0, "=> No value in this object - exiting!\n") if($DEBUG > 1);
		    next;
		} else {
		    &print_clients_amount();
		}
	    }
# }}}
	} elsif($tmp[0] == 2) {
	    # {{{ ------------------------------------- OID_BASE.2 
	    if($arg eq 'getnext') {
		# {{{ Get _next_ OID
		if(defined($tmp[5]) && ($tmp[2] >= 4)) {
		    # {{{ ------------------------------------- OID_BASE.2.tmp[1].tmp[2].tmp[3].tmp[4].tmp[5] 
		    # Specific client name
		    $CLIENT_NO = $tmp[3];
		    
		    # Specific job name
		    $JOB_NO = $tmp[4];
		    
		    # If tmp[2] 5-9
		    $STATUS_TYPE = $tmp[2] if(($tmp[2] >= 5) && ($tmp[2] <= 9));
		    
		    # Get the specific OID (tmp[5]) + 1
		    &echo(0, "=> Get next OID: $OID_BASE.2.1.",$tmp[2],".$CLIENT_NO.$JOB_NO.",$tmp[5]+1,"\n") if($DEBUG > 2);
		    if(!&call_func($tmp[2], $tmp[5]+1)) {
			$JOB_NO++; # Next job number
			
			if($DEBUG) {
			    &echo(0, "=> No OID at this level (-1) - get next branch OID: $OID_BASE.2.1.",$tmp[2],".$CLIENT_NO.$JOB_NO.1\n") if($DEBUG > 2);
			}
			
			if(!&call_func($tmp[2], 1)) {
			    $CLIENT_NO++; # Next client
			    $JOB_NO = 1;  # First job ID
			    
			    # If tmp[2] 5-9
			    $STATUS_TYPE = $tmp[2] if(($tmp[2] >= 5) && ($tmp[2] <= 9));
			    
			    if($DEBUG) {
				&echo(0, "=> No OID at this level (-2)- get next branch OID: $OID_BASE.2.1.",$tmp[2],".$CLIENT_NO.$JOB_NO.1\n") if($DEBUG > 2);
			    }
			    
			    if(!&call_func($tmp[2], 1)) {
				$CLIENT_NO = 1; # First client
				$JOB_NO = 1;    # First job ID
				$tmp[2]++;      # Next function type
				
				$STATUS_TYPE = $tmp[2] if($tmp[2] >= 5);
				
				if($DEBUG) {
				    &echo(0, "=> No OID at this level (-3) - get next branch OID: $OID_BASE.2.1.",$tmp[2],".$CLIENT_NO.$JOB_NO.1\n") if($DEBUG > 2);
				}
				
				&call_func($tmp[2], 1);
			    }
			}
		    }
# }}} # OID_BASE.2.1.3.tmp[3].tmp[4].tmp[5]
		} elsif(defined($tmp[4]) && ($tmp[2] == 3)) {
		    # {{{ ------------------------------------- OID_BASE.2.tmp[1].tmp[2].tmp[3].tmp[4]
		    # Specific client name
		    $CLIENT_NO = $tmp[3];
		    
		    if(!&call_func($tmp[2], $tmp[4]+1)) {
			# No OID at this level - get next branch OID, first value.
			$CLIENT_NO = $tmp[3]+1;
			
			if(!&call_func($tmp[2], 1)) {
			    # No OID at this level - get next branch OID, first value.
			    $CLIENT_NO = 1; # First client
			    $JOB_ID = 1; # First job ID
			    
			    $JOB_NO = 1 if(($tmp[2]+1) == 4);
			    &call_func($tmp[2]+1, 1);
			}
		    }
# }}} # OID_BASE.2.1.3.tmp[3].tmp[4]
		} else {
		    # {{{ ------------------------------------- OID_BASE.2.*
		    if(!defined($tmp[1]) || !defined($tmp[2])) {
			# {{{ --------------------------------- OID_BASE.2 
			# Get the first client number
			foreach my $client (@CLIENTS) {
			    next if(!$client);
			    $CLIENT_NO = (split(';', $client))[0];
			    last;
			}
			
			&call_func(1, 1);
# }}} OID_BASE.2
		    } else {
			# {{{ --------------------------------- OID_BASE.2.tmp[1].tmp[2].tmp[3] 
			if(defined($tmp[3])) {
#			if(!defined($tmp[4])) {
#			    $tmp[3] = $tmp[3];
#			} else {
			    $tmp[3]++;   # Next value
#			}
			} else {
			    $tmp[3] = 1; # Start with the first value
			}
# }}} OID_BASE.2.tmp[1].tmp[2].tmp[3]
			
			# {{{ --------------------------------- OID_BASE.2.tmp[1].tmp[2].tmp[3].tmp[4] 
			if($tmp[1] >= 3) {
			    if(defined($tmp[4])) {
				$tmp[4] = $JOB_NO;
			    } else {
				$tmp[4] = 1; # First job number
			    }
			}
# }}} OID_BASE.2.tmp[1].tmp[2].tmp[3].tmp[4]
			
			$CLIENT_NO = $tmp[3];
			$JOB_NO = $tmp[4] if(defined($tmp[4]));
			
			&output_extra_debugging(@tmp) if($DEBUG > 1);
			if(!&call_func($tmp[2], $tmp[3])) {
			    if($tmp[2]+1 == 3) {
				# Get the first client number
				foreach my $client (@CLIENTS) {
				    next if(!$client);
				    $CLIENT_NO = (split(';', $client))[0];
				    last;
				}
			    }
			    
			    # No OID at this level - get next branch OID, first value.
			    &call_func($tmp[2]+1, 1);
			}
		    }
# }}} OID_BASE.2.*
		}
# }}} # Next oid
	    } else {
		# {{{ Get _this_ OID
		if(!defined($tmp[1])) {
		    # {{{ ------------------------------------- OID_BASE.2 
		    &echo(0, "=> No value in this object - exiting!\n") if($DEBUG > 1);
		    next;
# }}}		    
		} elsif(!defined($tmp[2])) {
		    # {{{ ------------------------------------- OID_BASE.2.tmp[1] 
		    &echo(0, "=> No value in this object - exiting!\n") if($DEBUG > 1);
		    next;
# }}}		    
		} elsif(!defined($tmp[3])) {
		    # {{{ ------------------------------------- OID_BASE.2.tmp[1].tmp[2] 
		    &echo(0, "=> No value in this object - exiting!\n") if($DEBUG > 1);
		    next;
# }}}		    
		} elsif(defined($tmp[5]) && ($tmp[2] >= 4)) {
		    # {{{ ------------------------------------- OID_BASE.2.tmp[1].tmp[2].tmp[3].tmp[4].tmp[5] 
		    # If tmp[2] 5-9
		    $STATUS_TYPE = $tmp[2] if(($tmp[2] >= 5) && ($tmp[2] <= 9));
		    
		    # Specific client name
		    $CLIENT_NO = $tmp[3];
		    
		    # Specific job name
		    $JOB_NO = $tmp[4];
		    
		    # Specific job id
		    $JOB_ID = $tmp[5];
		    
		    &call_func($tmp[2], $tmp[5]);
# }}} # OID_BASE.2.1.3.tmp[3].tmp[4].tmp[5]
		} elsif(defined($tmp[4]) && ($tmp[2] == 3)) {
		    # {{{ ------------------------------------- OID_BASE.2.tmp[1].tmp[2].tmp[3].tmp[4] 
		    # Specific client name
		    $CLIENT_NO = $tmp[3];
		    
		    &call_func($tmp[2], $tmp[4]);
# }}} # OID_BASE.2.1.3.tmp[3].tmp[4]
		} elsif(!&call_func($tmp[2], $tmp[3])) {
		    # {{{ ------------------------------------- OID_BASE.2.tmp[1].tmp[2].tmp[3] 
		    &echo(0, "=> No value in this object - exiting!\n") if($DEBUG > 1);
		    next;
# }}} # OID_BASE.2.1.tmp[2].tmp[3]
		}
# }}} # This OID
	    }
# }}} # OID_BASE.2
	} else {
	    # {{{ ------------------------------------- OID_BASE.x 
	    &echo(0, "Error: No such OID '$OID_BASE.$oid'.\n") if($DEBUG);
	    next;
# }}} # No such OID
	}
    }
# }}}
}
