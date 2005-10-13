#!/usr/bin/perl -w

# {{{ $Id: bacula-snmp-stats.pl,v 1.10 2005-10-13 09:46:10 turbo Exp $
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

$ENV{PATH} = "/bin:/usr/bin:/usr/sbin";
my $DEBUG  = 0;

my $OID_BASE;
$OID_BASE = "OID_BASE"; # When debugging, it's easier to type this than the full OID
if($ENV{'MIBDIRS'}) {
    # ALWAYS override this if we're running through the SNMP daemon!
    $OID_BASE = ".1.3.6.1.4.1.8767.2.3"; # .iso.org.dod.internet.private.enterprises.bayourcom.snmp.baculastats
}
&echo(0, "=> OID_BASE => '$OID_BASE'\n") if($DEBUG);

# The 'flow' of the OID/MIB tree.
my %functions  = ($OID_BASE.".1"	=> "amount_clients",
		  $OID_BASE.".2"	=> "amount_types",
		  $OID_BASE.".3"	=> "amount_stats",

		  $OID_BASE.".4.1.1"	=> "clients_index",
		  $OID_BASE.".4.1.2"	=> "clients_name",
		  $OID_BASE.".4.1.3"	=> "jobs_name",

		  $OID_BASE.".5.1.1"	=> "types_index",
		  $OID_BASE.".5.1.2"	=> "types_names",
		  $OID_BASE.".5.1.3"	=> "jobs_ids",
		  $OID_BASE.".5.1.4"	=> "jobs_status"); # $OID_BASE.".5.1.[4-(4+9)]

# MIB tree 'flow' below the '$OID_BASE.5.3' branch.
my %keys       = ("1" => "start_date",
		  "2" => "end_date",
		  "3" => "duration",
		  "4" => "files",
		  "5" => "bytes");

# Some global data variables
my($oid, @Jobs, %STATUS, %Status, @CLIENTS);

# Total numbers
my($TYPES, $CLIENTS, $JOBS, $STATUS);

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

# {{{ OID tree
# smidump -f tree BAYOUR-COM-MIB.txt
# +--baculaStats(3)
#    |
#    +-- r-n Integer32 baculaTotalClients(1)
#    +-- r-n Integer32 baculaTotalTypes(2)
#    +-- r-n Integer32 baculaTotalStats(3)
#    |
#    +--baculaClientsTable(4)
#    |  |
#    |  +--baculaClientsEntry(1) [baculaIndexClients]
#    |     |
#    |     +-- --- CounterIndex  baculaIndexClients(1)
#    |     +-- r-n DisplayString baculaClientName(2)
#    |     +-- r-n DisplayString baculaJobName(3)
#    |
#    +--baculaStatsTable(5)
#       |
#       +--baculaStatsEntry(1) [baculaIndexClients,baculaIndexStats]
#          |
#          +-- --- CounterIndex  baculaIndexStats(1)
#          +-- r-n DisplayString baculaCounterName(2)
#          +-- r-n DisplayString baculaJobID(3)
#          +-- r-n DisplayString baculaDateStart(4)
#          +-- r-n DisplayString baculaDateEnd(5)
#          +-- r-n Integer32     baculaCompletionDuration(6)
#          +-- r-n Integer32     baculaCompletionFiles(7)
#          +-- r-n Integer32     baculaCompletionBytes(8)
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

# {{{ Get client names
sub get_clients {
    my $client = shift;
    my($clients, @clients);

    # Make sure the first (number '0') of the array is empty,
    # so we can start the OID's at '1'.
    push(@clients, '');

    my $sth = $dbh->prepare("SELECT ClientId,Name FROM Client WHERE Name LIKE '$client' ORDER BY ClientID")
	|| die("Could not prepare SQL query: $dbh->errstr\n");
    $sth->execute || die("Could not execute query: $sth->errstr\n");
    while( my @row = $sth->fetchrow_array() ) {
	push(@clients,  $row[0].";".$row[1]);
	$clients++; # Increase number of client counters
    }

    return($clients, @clients);
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

# {{{ Get next value from a set of input
sub get_next_oid {
    my @tmp = @_;

    &output_extra_debugging(@tmp) if($DEBUG > 3);

    # next1 => Base OID to use in call
    # next2 => next1.next2 => Full OID to retreive
    # next3 => Client number (OID_BASE.4) or Job ID (OID_BASE.5)
    my($next1, $next2, $next3);

    $next1 = $OID_BASE.".".$tmp[0].".".$tmp[1].".".$tmp[2]; # Base value.
    if(defined($tmp[5])) {
	$next2 = ".".$tmp[3].".".$tmp[4];
	$next3 = $tmp[5];
    } elsif(defined($tmp[4])) {
	$next2 = ".".$tmp[3];
	$next3 = $tmp[4];
    } else {
	$next2 = "";
	$next3 = $tmp[3];
    }

    # Global variables for the print function(s).
    if($tmp[0] == 5) {
	if($tmp[2] <= 3) {
	    # StatsIndex, StatsTypesName and JobID list
	    $STATUS_TYPE = $tmp[2];
	    $CLIENT_NO   = $tmp[3];
	    $JOB_NO      = $tmp[4];
	} elsif($tmp[2] >= 4) {
	    # Statistic counters
	    $STATUS_TYPE = $tmp[2] - 3; # Offset three because of index etc.
	    $CLIENT_NO   = $tmp[3];
	    $JOB_NO      = $tmp[4];
	}
    } else {
	$CLIENT_NO   = $tmp[3];
	$STATUS_TYPE = $tmp[4];
    }

    my $string;
    $string  = "STATUS_TYPE=$STATUS_TYPE" if(defined($STATUS_TYPE));
    $string .= ", " if($string);
    $string .= "CLIENT_NO=$CLIENT_NO" if(defined($CLIENT_NO));
    $string .= ", " if($string);
    $string .= "JOB_NO=$JOB_NO" if(defined($JOB_NO));

    &echo(0, "=> get_next_oid(): $string\n") if($DEBUG > 2);
    return($next1, $next2, $next3);
}
# }}}


# ====================================================
# =====       P R I N T  F U N C T I O N S       =====

# {{{ OID_BASE.1.0		Output total number of client counters
sub print_amount_clients {
    if($DEBUG) {
	&echo(0, "=> OID_BASE.totalClients.0\n") if($DEBUG > 1);
	&echo(0, "$OID_BASE.1.0 $CLIENTS\n");
    }

    &echo(1, "$OID_BASE.1.0\n");
    &echo(1, "integer\n");
    &echo(1, "$CLIENTS\n");

    return 1;
}
# }}}

# {{{ OID_BASE.2.0		Output total number of type counters
sub print_amount_types {
    if($DEBUG) {
	&echo(0, "=> OID_BASE.totalTypes.0\n") if($DEBUG > 1);
	&echo(0, "$OID_BASE.2.0 $TYPES\n");
    }

    &echo(1, "$OID_BASE.2.0\n");
    &echo(1, "integer\n");
    &echo(1, "$TYPES\n");

    return 1;
}
# }}}

# {{{ OID_BASE.3.0		Output total number of statistic counters
sub print_amount_stats {
    if($DEBUG) {
	&echo(0, "=> OID_BASE.totalStats.0\n") if($DEBUG > 1);
	&echo(0, "$OID_BASE.3.0 $STATUS\n");
    }

    &echo(1, "$OID_BASE.3.0\n");
    &echo(1, "integer\n");
    &echo(1, "$STATUS\n");

    return 1;
}
# }}}


# {{{ OID_BASE.4.1.1.x		Output client index
sub print_clients_index {
    my $client_no = shift; # Client number
    my($i, $max);
    my $success = 0;
    &echo(0, "=> OID_BASE.clientTable.clientEntry.IndexClients\n") if($DEBUG > 1);

    if(defined($client_no)) {
	# {{{ Specific client index
	if(!$CLIENTS[$client_no]) {
	    &echo(0, "=> No value in this object ($client_no)\n") if($DEBUG);
	    return 0;
	}
    
	$i = $client_no;
	$max = $client_no;
# }}}
    } else {
	# {{{ The FULL client index
	$i = 1;
	$max = $CLIENTS;
# }}}
    }

    # {{{ Output index
    for(; $i <= $max; $i++) {
	&echo(0, "$OID_BASE.4.1.1.$i $i\n") if($DEBUG);

	&echo(1, "$OID_BASE.4.1.1.$i\n");
	&echo(1, "integer\n");
	&echo(1, "$i\n");

	$success = 1;
    }
# }}}

    return $success;
}
# }}}

# {{{ OID_BASE.4.1.2.x		Output client name
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
	$max = $client_no;
# }}}
    } else {
	# {{{ ALL client names
	$i = 1;
	$max = $CLIENTS;
# }}}
    }

    # {{{ Output client names
    for(; $i <= $max; $i++) {
	my ($client_nr, $client_name) = split(';', $CLIENTS[$i]);
	
	&echo(0, "$OID_BASE.4.1.2.$client_nr $client_name\n") if($DEBUG);

	&echo(1, "$OID_BASE.4.1.2.$client_nr\n");
	&echo(1, "string\n");
	&echo(1, "$client_name\n");
    }
# }}}

    return 1;
}
# }}}

# {{{ OID_BASE.4.1.3.x.y	Output job name
sub print_jobs_name {
    my $jobnr = shift; # Job number
    my $success = 0;
    &echo(0, "=> OID_BASE.clientTable.clientEntry.jobName\n") if($DEBUG > 1);

    if(defined($CLIENT_NO)) {
	# {{{ Specific clients job name
	if(!$CLIENTS[$CLIENT_NO]) {
	    &echo(0, "=> No value in this object\n") if($DEBUG > 1);
	    return 0;
	}
    
	# Get client name from the client number.
	my ($client_no, $client_name) = split(';', $CLIENTS[$CLIENT_NO]);

	my $job_num = 1;
	foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
	    if($job_num == $jobnr) {
		&echo(0, "$OID_BASE.4.1.3.$client_no.$job_num $job_name\n") if($DEBUG);

		&echo(1, "$OID_BASE.4.1.3.$client_no.$job_num\n");
		&echo(1, "string\n");
		&echo(1, "$job_name\n");

		$success = 1;
	    }
	    
	    $job_num++;
	}
# }}}
    } else {
	# {{{ ALL clients job names
	my $client_num  = 1;
	foreach my $client_name (keys %STATUS) {
	    my $job_num = 1;
	    foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
		&echo(0, "$OID_BASE.4.1.3.$client_num.$job_num $job_name\n") if($DEBUG);

		&echo(1, "$OID_BASE.4.1.3.$client_num.$job_num\n");
		&echo(1, "string\n");
		&echo(1, "$job_name\n");
		
		$success = 1;
		$job_num++;
	    }

	    $client_num++;
	}
# }}}
    }

    return $success;
}
# }}}


# {{{ OID_BASE.5.1.1.a		Output job status index
sub print_types_index {
    my $key_nr = shift;
    my $success = 0;
    my($i, $max);

    &echo(0, "=> OID_BASE.statsTable.statsEntry.IndexStats\n") if($DEBUG > 1);
    if(defined($key_nr)) {
	# {{{ One specific status index number
	if(!$keys{$key_nr}) {
	    &echo(0, "=> No such status type ($key_nr)\n") if($DEBUG > 1);
	    return 0;
	}

	$i = $key_nr;
	$max = $key_nr;
# }}}
    } else {
	# {{{ ALL status indexes
	$i = 1;
	$max = $TYPES;
# }}}
    }

    # {{{ Output index
    for(; $i <= $max; $i++) {
	my $key_name = $keys{$i};
	
	&echo(0, "$OID_BASE.5.1.1.$i $i\n") if($DEBUG);
	
	&echo(1, "$OID_BASE.5.1.1.$i\n");
	&echo(1, "integer\n");
	&echo(1, "$i\n");
	
	$success = 1;
    }
# }}}

    return $success;
}
# }}}

# {{{ OID_BASE.5.1.2.a		Output the types
sub print_types_names {
    my $key_nr = shift;
    my $success = 0;
    my($i, $max);

    &echo(0, "=> OID_BASE.statsTable.statsEntry.statsTypeName\n") if($DEBUG > 1);
    if(defined($key_nr)) {
	# {{{ One specific type name
	if(!$keys{$key_nr}) {
	    &echo(0, "=> No such status type ($key_nr)\n") if($DEBUG > 1);
	    return 0;
	}

	$i = $key_nr;
	$max = $key_nr;
# }}}
    } else {
	# {{{ ALL status indexes
	$i = 1;
	$max = $TYPES;
# }}}
    }

    # {{{ Output index
    for(; $i <= $max; $i++) {
	my $key_name = $keys{$i};
	
	&echo(0, "$OID_BASE.5.1.2.$i $key_name\n") if($DEBUG);
	
	&echo(1, "$OID_BASE.5.1.2.$i\n");
	&echo(1, "string\n");
	&echo(1, "$key_name\n");
	
	$success = 1;
    }
# }}}

    return $success;
}
# }}}

# {{{ OID_BASE.5.1.3.x.y.z	Output the job ID's
sub print_jobs_ids {
    my $job_name_nr = shift;
    my $success = 0;

    if(defined($CLIENT_NO)) {
	# {{{ Job ID for a specific client and a specific job name
	if(!$CLIENTS[$CLIENT_NO]) {
	    &echo(0, "=> No value in this object\n") if($DEBUG > 1);
	    return 0;
	}

	&echo(0, "=> OID_BASE.statsTable.statsEntry.clientID.jobID\n") if($DEBUG > 1);

	# Get client name from the client number (which is a global variable).
	my($client_no, $client_name) = split(';', $CLIENTS[$CLIENT_NO]);

	# Get the job name requested
	my $job_name_num = 1;
	foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
	    if($job_name_num == $JOB_NO) {
		my $job_id_num = 1;
		foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
		    if($job_id_num == $job_name_nr) {
			&echo(0, "$OID_BASE.5.1.3.$client_no.$job_name_num.$job_id_num $job_id\n") if($DEBUG);
			
			&echo(1, "$OID_BASE.5.1.3.$client_no.$job_name_num.$job_id_num\n");
			&echo(1, "string\n");
			&echo(1, "$job_id\n");
			
			$success = 1;
		    }
		    
		    $job_id_num++;
		}
	    }

	    $job_name_num++;
	}
# }}}
    } else {
	# {{{ ALL clients, all job status
	my $client_name_num = 1;
	&echo(0, "=> OID_BASE.statsTable.statsEntry.clientID.jobID\n") if($DEBUG > 1);
	foreach my $client_name (keys %STATUS) {
	    my $job_name_num = 1;
	    &echo(0, "=> Client name: '$client_name'\n") if($DEBUG > 3);
	    foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
		my $job_id_num = 1;
		&echo(0, "=>   Job name: '$job_name'\n") if($DEBUG > 3);
		foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
		    &echo(0, "=>     Job ID: '$job_id'\n") if($DEBUG > 3);

		    &echo(0, "$OID_BASE.5.1.3.$client_name_num.$job_name_num.$job_id_num $job_id\n") if($DEBUG);
		    
		    &echo(1, "$OID_BASE.5.1.3.$client_name_num.$job_name_num.$job_id_num\n");
		    &echo(1, "string\n");
		    &echo(1, "$job_id\n");
		    
		    $success = 1;
		    $job_id_num++;
		}

		$job_name_num++;
	    }

	    $client_name_num++;
	}
# }}}
    }

    return $success;
}
# }}}

# {{{ OID_BASE.5.1.a.x.y.z	Output job status
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
	my($client_no, $client_name) = split(';', $CLIENTS[$CLIENT_NO]);

	# Get the key name from the key number (which is a global variable).
	my $key_name;
	if(!$keys{$STATUS_TYPE}) {
	    &echo(0, "=> No value in this object\n") if($DEBUG > 1);
	    return 0;
	} else {
	    $key_name = $keys{$STATUS_TYPE};
	}
	my $type = $STATUS_TYPE + 3; # Offset three because of index etc.

	my $i=1; # Job Name
	foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
	    if($i == $JOB_NO) {
		my $j=1; # Job ID

		&echo(0, "=> OID_BASE.statsTable.statsEntry.$key_name.clientId.jobNr\n") if($DEBUG > 1);
		foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
		    if($j == $job_status_nr) {
			&echo(0, "$OID_BASE.5.1.$type.$client_no.$i.$j ".$STATUS{$client_name}{$job_name}{$job_id}{$key_name}."\n") if($DEBUG);

			&echo(1, "$OID_BASE.5.1.$type.$client_no.$i.$j\n");
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
	    my $type_nr = $key_nr + 3; # Offset three because of index etc.
	    &echo(0, "=> OID_BASE.statsTable.statsEntry.$key_name.clientId.jobNr\n") if($DEBUG > 1);

	    my $client_num = 1;
	    foreach my $client_name (keys %STATUS) {
		my $job_name_num = 1;
		foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
		    my $job_id_num = 1;
		    foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
			&echo(0, "$OID_BASE.5.1.$type_nr.$client_num.$job_name_num.$job_id_num ".$STATUS{$client_name}{$job_name}{$job_id}{$key_name}."\n") if($DEBUG);

			&echo(1, "$OID_BASE.5.1.$type_nr.$client_num.$job_name_num.$job_id_num\n");
			if(($key_name eq 'start_date') || ($key_name eq 'end_date')) {
			    &echo(1, "string\n");
			} else {
			    &echo(1, "integer\n");
			}
			&echo(1, $STATUS{$client_name}{$job_name}{$job_id}{$key_name}."\n");
			
			$success = 1;
			$job_id_num++;
		    }

		    $job_name_num++;
		}

		$client_num++;
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
    my $function;

    $func_arg = '' if(!$func_arg);

    &echo(0, "=> call_func($func_nr, $func_arg)\n") if($DEBUG > 2);
    my $func = $functions{$func_nr};
    if($func) {
	$function = "print_".$func;
    } else {
	foreach my $oid (sort keys %functions) {
	    # Take the very first match
	    if($oid =~ /^$func_nr/) {
		&echo(0, "=> '$oid =~ /^$func_nr/'\n") if($DEBUG > 2);
		$function = "print_".$functions{$oid};
		last;
	    }
	}
    }

    &echo(0, "=> Calling function '$function($func_arg)'\n") if($DEBUG > 1);
    
    $function = \&{$function}; # Because of 'use strict' above...
    &$function($func_arg);
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
    if($DEBUG) {
	if(&open_log()) {
	    $log_opened = 1;
	    open(STDERR, ">&LOG") if(($DEBUG <= 2) || $ENV{'MIBDIRS'});
	}
    }

    if($stdout) {
	print $string;
    } elsif($log_opened) {
	print LOG &get_timestring()," " if($DEBUG > 2);
	print LOG $string;
    }
}
# }}}

# {{{ Load all information needed
sub load_information {
    # {{{ How many base counters?
    foreach (keys %keys) {
	$TYPES++;
    }
    # }}}

    # {{{ Load configuration file and connect to SQL server.
    &get_config();
    &sql_connect();
    # }}}

    # {{{ Get names of all clients (in alphabetical order).
    ($CLIENTS, @CLIENTS) = &get_clients("%");
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
	    $JOBS++; # Increase number of job counters
	    
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

		$STATUS++; # Increase number of status counters
	    }
	}
    }
    # }}}

    # {{{ Rearrange the CLIENTS array, so they come in the same order as the STATUS array
    undef @CLIENTS;
    my $i = 1;
    foreach my $client_name (keys %STATUS) {
	$CLIENTS[$i] = $i.";".$client_name;
	$i++;
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
    foreach my $oid (sort keys %functions) {
	my $func = $functions{$oid};
	if($func) {
	    $func = \&{"print_".$func}; # Because of 'use strict' above...
	    &$func();
	}
    }
# }}}
} else {
    # {{{ Add the '%keys' array to the '%functions' array
    # First one is already there, so start with the second with value '5'...
    # We do that here instead of at the very top so that output of ALL
    # works without calling print_jobs_status() FIVE times...
    my($i, $j) = (2, 5);
    for(; $keys{$i}; $i++, $j++) {
	$functions{$OID_BASE.".5.1.$j"} = "jobs_status";
    }
# }}}

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
	$oid =~ s/OID_BASE//;  # Remove the OID base (if we're debugging)
	$oid =~ s/^\.//;       # Remove the first dot if it exists - it's in the way!
	&echo(0, "=> OID=$oid\n") if($DEBUG > 1);
	
	my @tmp = split('\.', $oid);
	&output_extra_debugging(@tmp) if($DEBUG > 1);
# }}}
	
	if(!defined($tmp[0])) {
	    # {{{ ------------------------------------- OID_BASE   
	    &call_func($OID_BASE.".1");
# }}} # OID_BASE
	} elsif(($tmp[0] >= 1) && ($tmp[0] <= 3)) {
	    # {{{ ------------------------------------- OID_BASE.[1-3] 
	    if($arg eq 'getnext') {
		# {{{ Get _next_ OID
		if(!defined($tmp[1])) {
		    &call_func($OID_BASE.".".$tmp[0]);
		} else {
		    my $new = $tmp[0]+1;

		    if($new >= 4) {
			&call_func($OID_BASE.".".$new, 1);
		    } else {
			&call_func($OID_BASE.".".$new);
		    }
		}
# }}} # Get next OID
	    } else {
		# {{{ Get _this_ OID
		if(!defined($tmp[1])) {
		    &echo(0, "=> No value in this object - exiting!\n") if($DEBUG > 1);

		    &echo(1, "NONE\n");
		    &echo(0, "\n") if($DEBUG > 1);
		    next;
		} else {
		    &call_func($OID_BASE.".".$tmp[0]);
		}
# }}} # Get this OID
	    }
# }}} # OID_BASE.[1-3]
	} elsif(($tmp[0] >= 4) && ($tmp[0] <= 5)) {
	    # {{{ ------------------------------------- OID_BASE.[4-5] 
	    if($arg eq 'getnext') {
		# {{{ Get _next_ OID
		# {{{ Figure out the NEXT value from the input
		# $tmp[x]: 0 1 2 3 4 5
		# ====================
		# OID_BASE.4.1.1.x
		# OID_BASE.4.1.2.x
		# OID_BASE.4.1.3.x.y
		#
		# OID_BASE.5.1.1.a
		# OID_BASE.5.1.2.a
		# OID_BASE.5.1.a.x.y.z
		# ======================
		# $tmp[x]: 0 1 2 3 4 5
		if(!defined($tmp[1])) {
		    $tmp[1] = 1;
		    $tmp[2] = 1;
		    $tmp[3] = 1;
		} else {
		    if(!defined($tmp[2])) {
			$tmp[2] = 1;
			$tmp[3] = 1;
		    } else {
			if(!defined($tmp[3])) {
			    $tmp[3] = 1;
			} else {
			    if($tmp[2] == 3) {
				if(!defined($tmp[4])) {
				    $tmp[4] = 1;
				} else {
				    if($tmp[0] == 5) {
					if(!defined($tmp[5])) {
					    $tmp[5] = 1;
					} else {
					    $tmp[5] += 1;
					}
				    } else {
					$tmp[4] += 1;
				    }
				}
			    } else {
				if(($tmp[0] == 5) && ($tmp[2] >= 4)) {
				    $tmp[5] += 1;
				} else {
				    $tmp[3] += 1;
				}
			    }
			}
		    }
		}

		# How to call call_func()
		my($next1, $next2, $next3) = get_next_oid(@tmp);
# }}} # Get the next value
		
		# {{{ Call functions, recursivly
		&echo(0, "=> Get next OID: $next1$next2.$next3\n") if($DEBUG > 2);
		if(!&call_func($next1, $next3)) {
		    # {{{ Figure out the NEXT value from the input
		    if($tmp[2] >= 3) {
			if($tmp[0] == 4) {
			    # OID_BASE.4
			    $tmp[3]++;
			    $tmp[4] = 1;
			} else {
			    # OID_BASE.5
			    if(!defined($tmp[4])) {
				$tmp[4] = 1;
				$tmp[5] = 1;
			    } else {
				if(!defined($tmp[5])) {
				    $tmp[5] = 1;
				} else {
				    if($tmp[2] >= 3) {
					$tmp[4]++;
					$tmp[5] = 1;
				    } else {
					$tmp[5]++;
				    }
				}
			    }
			}
		    } else {
			$tmp[2]++;
			$tmp[3]  = 1;

			if(($tmp[0] == 5) && ($tmp[2] == 3)) {
			    # OID_BASE.5
			    if(!defined($tmp[4])) {
				$tmp[4] = 1;
				$tmp[5] = 1;
			    } else {
				if(!defined($tmp[5])) {
				    $tmp[5] = 1;
				} else {
				    $tmp[5]++;
				}
			    }
			}
		    }

		    # How to call call_func()
		    my($next1, $next2, $next3) = get_next_oid(@tmp);
# }}} # Get the next value

		    &echo(0, "=> No OID at that level (-1) - get next branch OID: $next1$next2.$next3\n") if($DEBUG > 2);
		    if(!&call_func($next1, $next3)) {
			# {{{ Figure out the NEXT value from the input
			if($tmp[0] == 4) {
			    # OID_BASE.4
			    $tmp[0]++;
			    $tmp[1] = 1;
			    $tmp[2] = 1;
			    $tmp[3] = 1;
			} elsif($tmp[2] >= 3) {
			    $tmp[3]++;
			    $tmp[4] = 1;
			    $tmp[5] = 1;
			} else {
			    $tmp[4]++;
			    $tmp[5] = 1;
			}

			# How to call call_func()
			my($next1, $next2, $next3) = get_next_oid(@tmp);
# }}} # Get the next value

			&echo(0, "=> No OID at that level (-2) - get next branch OID: $next1$next2.$next3\n") if($DEBUG > 2);
			if(!&call_func($next1, $next3)) {
			    # {{{ Figure out the NEXT value from the input
			    # This should be quite simple. It is only (?) called in the
			    # OID_BASE.5.1.3 branch which is two extra oid levels 'deep'.
			    # Input: OID_BASE.5.1.3.4.9.2
			    #     1: OID_BASE.5.1.3.4.9.3
			    #    -1: OID_BASE.5.1.3.4.10.3
			    #    -2: OID_BASE.5.1.3.5.1.1
			    #    -3: OID_BASE.5.1.4.1.1.1 <- here
			    if($tmp[2] >= 3) {
				$tmp[2]++;
				$tmp[3] = 1 if(defined($tmp[3]));
			    } else {
				$tmp[3]++;
			    }
			    $tmp[4] = 1 if(defined($tmp[4]));
			    $tmp[5] = 1 if(defined($tmp[5]));

			    # How to call call_func()
			    my($next1, $next2, $next3) = get_next_oid(@tmp);
# }}} # Get the next value

			    &echo(0, "=> No OID at that level (-3) - get next branch OID: $next1$next2.$next3\n") if($DEBUG > 2);
			    &call_func($next1, $next3);
			}
		    }
		}
# }}} # Call functions
# }}} # Get _next_ OID
	    } else {
		# {{{ Get _this_ OID
		if((($tmp[0] == 4) && (!defined($tmp[1]) || !defined($tmp[2]) || !defined($tmp[3]))) ||
		   (($tmp[0] == 5) && (!defined($tmp[1]) || !defined($tmp[2]))))
		{
		    &echo(0, "=> No value in this object - exiting!\n") if($DEBUG > 1);

		    &echo(1, "NONE\n");
		    &echo(0, "\n") if($DEBUG > 1);
		    next;
		} else {
		    # How to call call_func()
		    my($next1, $next2, $next3) = get_next_oid(@tmp);

		    &echo(0, "=> Get this OID: $next1$next2.$next3\n") if($DEBUG > 2);
		    &call_func($next1, $next3);
		}
# }}} # Get _this_ OID
	    }
# }}} # OID_BASE.[4-5]
	} else {
	    # {{{ ------------------------------------- Unknown OID 
	    &echo(0, "Error: No such OID '$OID_BASE' . '$oid'.\n") if($DEBUG);
	    &echo(0, "\n") if($DEBUG > 1);
	    next;
# }}} # No such OID
	}

	&echo(0, "\n") if($DEBUG > 1);
    }
# }}}
}
