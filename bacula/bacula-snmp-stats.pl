#!/usr/bin/perl -w

# {{{ $Id: bacula-snmp-stats.pl,v 1.11 2005-10-14 10:00:23 turbo Exp $
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
#	DEBUG=
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
my %CFG;

my $OID_BASE;
$OID_BASE = "OID_BASE"; # When debugging, it's easier to type this than the full OID
if($ENV{'MIBDIRS'}) {
    # ALWAYS override this if we're running through the SNMP daemon!
    $OID_BASE = ".1.3.6.1.4.1.8767.2.3"; # .iso.org.dod.internet.private.enterprises.bayourcom.snmp.baculastats
}

# The 'flow' of the OID/MIB tree.
my %functions  = (# baculaTotal*	Total counters
		  $OID_BASE.".1"	=> "amount_clients",
		  $OID_BASE.".2"	=> "amount_types",
		  $OID_BASE.".3"	=> "amount_stats",
		  $OID_BASE.".4"	=> "amount_pools",
		  $OID_BASE.".5"	=> "amount_medias",

		  # baculaClientsTable	The client information
		  $OID_BASE.".6.1.1"	=> "clients_index",
		  $OID_BASE.".6.1.2"	=> "clients_counter",
		  $OID_BASE.".6.1.3"	=> "clients_name",

		  # baculaStatsTable	The status information
		  $OID_BASE.".7.1.1"	=> "types_index",
		  $OID_BASE.".7.1.2"	=> "types_names",
		  $OID_BASE.".7.1.3"	=> "jobs_ids",
		  $OID_BASE.".7.1.4"	=> "jobs_status",	# $OID_BASE.7.1.[4-(4+9)]

		  # baculaPoolsTable	The pool information
		  $OID_BASE.".8.1.1"	=> "pool_index",
		  $OID_BASE.".8.1.2"	=> "pool_counter",
		  $OID_BASE.".8.1.3"	=> "pool_names",

		  # baculaMediaTable	The media information
		  $OID_BASE.".9.1.1"	=> "media_index",
		  $OID_BASE.".9.1.2"	=> "media_counter",
		  $OID_BASE.".9.1.3"	=> "media_names");


# MIB tree 'flow' below the '$OID_BASE.7.3' branch.
my %keys_stats  = ("1"  => "start_date",
		   "2"  => "end_date",
		   "3"  => "duration",
		   "4"  => "files",
		   "5"  => "bytes");

my %keys_client = ("1"  => "id",
		   "2"  => "uname",
		   "3"  => "auto_prune",
		   "4"  => "file_retention",
		   "5"  => "job_retention");

my %keys_pool   = ("01" => "id",
		   "02" => "num_vols",
		   "03" => "max_vols",
		   "04" => "use_once",
		   "05" => "use_catalog",
		   "06" => "accept_any_vol",
		   "07" => "vol_retention",
		   "08" => "vol_use_duration",
		   "09" => "max_jobs",
		   "10" => "max_files",
		   "11" => "max_bytes",
		   "12" => "auto_prune",
		   "13" => "recycle",
		   "14" => "type",
		   "15" => "label_format",
		   "16" => "enabled",
		   "17" => "scratch_pool",
		   "18" => "recycle_pool");

my %keys_media  = ("01" => "id",
		   "02" => "slot",
		   "03" => "pool",
		   "04" => "type",
		   "05" => "first_written",
		   "06" => "last_written",
		   "07" => "label_date",
		   "08" => "jobs",
		   "09" => "files",
		   "10" => "blocks",
		   "11" => "mounts",
		   "12" => "bytes",
		   "13" => "errors",
		   "14" => "writes",
		   "15" => "capacity",
		   "16" => "status",
		   "17" => "recycle",
		   "18" => "retention",
		   "19" => "use_duration",
		   "20" => "max_jobs",
		   "21" => "max_files",
		   "22" => "max_bytes",
		   "23" => "in_changer",
		   "24" => "media_addressing",
		   "25" => "read_time",
		   "26" => "write_time",
		   "26" => "end_file",
		   "27" => "end_block");

# Some global data variables
my($oid, %STATUS, %POOLS, %MEDIAS, @CLIENTS, %CLIENTS);

# Total numbers
my($TYPES_STATS, $TYPES_CLIENT, $TYPES_POOL, $TYPES_MEDIA);
my($CLIENTS, $JOBS, $STATUS, $POOLS, $MEDIAS);

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
# which type of status wanted (from %keys_stats above).
my($TYPE_STATUS);

# This is for the print_clients_name() function to know
# which type of information wanted (from %keys_client
# above).
my($TYPE_CLIENT);

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
#    +-- r-n Integer32 baculaTotalPools(4)
#    +-- r-n Integer32 baculaTotalMedia(5)
#    |
#    +--baculaClientsTable(6)
#    |  |
#    |  +--baculaClientsEntry(1) [baculaClientsIndex]
#    |     |
#    |     +-- --- CounterIndex  baculaClientsIndex(1)
#    |     +-- r-n DisplayString baculaClientCounter(2)
#    |     +-- r-n DisplayString baculaClientName(3)
#    |     +-- r-n DisplayString baculaClientUname(4)
#    |     +-- rwn DisplayString baculaClientAutoPrune(5)
#    |     +-- rwn DisplayString baculaClientRetentionFile(6)
#    |     +-- rwn DisplayString baculaClientRetentionJob(7)
#    |
#    +--baculaStatsTable(7)
#    |  |
#    |  +--baculaStatsEntry(1) [baculaClientsIndex,baculaStatsIndex]
#    |     |
#    |     +-- --- CounterIndex  baculaStatsIndex(1)
#    |     +-- r-n DisplayString baculaStatsCounter(2)
#    |     +-- r-n Integer32     baculaStatsJobNr(3)
#    |     +-- r-n DisplayString baculaStatsClient(4)
#    |     +-- r-n DisplayString baculaStatsJobName(5)
#    |     +-- r-n DisplayString baculaStatsJobID(6)
#    |     +-- r-n TimeStamp     baculaStatsStart(7)
#    |     +-- r-n TimeStamp     baculaStatsEnd(8)
#    |     +-- r-n Integer32     baculaStatsDuration(9)
#    |     +-- r-n Integer32     baculaStatsFiles(10)
#    |     +-- r-n Integer32     baculaStatsBytes(11)
#    |     +-- r-n JobType       baculaStatsType(12)
#    |     +-- r-n Status        baculaStatsStatus(13)
#    |     +-- r-n Level         baculaStatsLevel(14)
#    |     +-- r-n Integer32     baculaStatsErrors(15)
#    |     +-- r-n Integer32     baculaStatsMissingFiles(16)
#    |
#    +--baculaPoolsTable(8)
#    |  |
#    |  +--baculaPoolsEntry(1) [baculaPoolsIndex]
#    |     |
#    |     +-- --- CounterIndex  baculaPoolsIndex(1)
#    |     +-- r-n DisplayString baculaPoolsName(2)
#    |     +-- r-n Integer32     baculaPoolsNum(3)
#    |     +-- r-n Integer32     baculaPoolsMax(4)
#    |     +-- rwn TrueFalse     baculaPoolsUseOnce(5)
#    |     +-- rwn TrueFalse     baculaPoolsUseCatalog(6)
#    |     +-- rwn TrueFalse     baculaPoolsAcceptAnyVolume(7)
#    |     +-- rwn Integer32     baculaPoolsRetention(8)
#    |     +-- rwn Integer32     baculaPoolsDuration(9)
#    |     +-- rwn Integer32     baculaPoolsMaxJobs(10)
#    |     +-- rwn Integer32     baculaPoolsMaxFiles(11)
#    |     +-- rwn Integer32     baculaPoolsMaxBytes(12)
#    |     +-- rwn TrueFalse     baculaPoolsAutoPrune(13)
#    |     +-- rwn TrueFalse     baculaPoolsRecycle(14)
#    |     +-- rwn PoolType      baculaPoolsType(15)
#    |     +-- rwn DisplayString baculaPoolsLabelFormat(16)
#    |     +-- rwn TrueFalse     baculaPoolsEnabled(17)
#    |     +-- r-n Integer32     baculaPoolsScratchPoolID(18)
#    |     +-- r-n Integer32     baculaPoolsRecyclePoolID(19)
#    |
#    +--baculaMediaTable(9)
#       |
#       +--baculaMediaEntry(1) [baculaMediaIndex]
#          |
#          +-- --- CounterIndex  baculaMediaIndex(1)
#          +-- r-n DisplayString baculaMediaName(2)
#          +-- r-n Integer32     baculaMediaSlot(3)
#          +-- r-n TimeStamp     baculaMediaWrittenFirst(4)
#          +-- r-n TimeStamp     baculaMediaWrittenLast(5)
#          +-- r-n Integer32     baculaMediaJobs(6)
#          +-- r-n Integer32     baculaMediaFiles(7)
#          +-- r-n Integer32     baculaMediaBlocks(8)
#          +-- r-n Integer32     baculaMediaMounts(9)
#          +-- r-n Integer32     baculaMediaBytes(10)
#          +-- r-n Integer32     baculaMediaErrors(11)
#          +-- r-n Integer32     baculaMediaWrites(12)
#          +-- r-n Integer32     baculaMediaCapacity(13)
#          +-- r-n VolumeStatus  baculaMediaStatus(14)
#          +-- r-n TrueFalse     baculaMediaRecycle(15)
#          +-- r-n Integer32     baculaMediaRetention(16)
#          +-- r-n Integer32     baculaMediaDuration(17)
#          +-- r-n Integer32     baculaMediaMaxJobs(18)
#          +-- r-n Integer32     baculaMediaMaxFiles(19)
#          +-- r-n Integer32     baculaMediaMaxBytes(20)
#          +-- r-n TrueFalse     baculaMediaInChanger(21)
#          +-- r-n TrueFalse     baculaMediaMediaAddressing(22)
#          +-- r-n Integer32     baculaMediaReadTime(23)
#          +-- r-n Integer32     baculaMediaWriteTime(24)
#          +-- r-n Integer32     baculaMediaEndFile(25)
#          +-- r-n Integer32     baculaMediaEndBlock(26)
# }}}

# ====================================================
# =====    R E T R E I V E  F U N C T I O N S    =====

# {{{ Load the information needed to connect to the MySQL server.
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

    # Just incase any of these isn't set, initialize the variable.
    $CFG{'USERNAME'}	= '' if(!defined($CFG{'USERNAME'}));
    $CFG{'PASSWORD'}	= '' if(!defined($CFG{'PASSWORD'}));
    $CFG{'DB'}		= '' if(!defined($CFG{'DB'}));
    $CFG{'HOST'}	= '' if(!defined($CFG{'HOST'}));
    $CFG{'CATALOG'}	= '' if(!defined($CFG{'CATALOG'}));
    $CFG{'DEBUG'}	= 0  if(!defined($CFG{'DEBUG'}));
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

	exit 1 if($CFG{'DEBUG'});
    }
}
# }}}

# {{{ Get client information
sub get_info_client {
    my($QUERY, $client, %client);

    # {{{ Setup and execute the SQL query
    $QUERY  = "SELECT * FROM Client";
    my $sth = $dbh->prepare($QUERY) || die("Could not prepare SQL query: $dbh->errstr\n");
    $sth->execute || die("Could not execute query: $sth->errstr\n");
# }}}

    while( my @row = $sth->fetchrow_array() ) {
	# {{{ Put toghether the client array
	$client{$row[1]}{"id"}			= $row[1];
	$client{$row[1]}{"uname"}		= $row[2];
	$client{$row[1]}{"auto_prune"}		= $row[3];
	$client{$row[1]}{"file_retention"}	= $row[4];
	$client{$row[1]}{"job_retention"}	= $row[5];
# }}}

	# Increase number of status counters
	$client++;
    }

    return($client, %client);
}
# }}}

# {{{ Get pool information
sub get_info_pool {
    my($QUERY, $pool, %pool);

    # Setup and execute the SQL query
    $QUERY  = "SELECT * FROM Pool";
    my $sth = $dbh->prepare($QUERY) || die("Could not prepare SQL query: $dbh->errstr\n");
    $sth->execute || die("Could not execute query: $sth->errstr\n");

    while( my @row = $sth->fetchrow_array() ) {
	# {{{ Put toghether the pool array
	$pool{$row[1]}{"id"}			= $row[1];
	$pool{$row[1]}{"num_vols"}		= $row[2];
	$pool{$row[1]}{"max_vols"}		= $row[3];
	$pool{$row[1]}{"use_once"}		= $row[4];
	$pool{$row[1]}{"use_catalog"}		= $row[5];
	$pool{$row[1]}{"accept_any_vol"}	= $row[6];
	$pool{$row[1]}{"vol_retention"}		= $row[7];
	$pool{$row[1]}{"vol_use_duration"}	= $row[8];
	$pool{$row[1]}{"max_jobs"}		= $row[9];
	$pool{$row[1]}{"max_files"}		= $row[10];
	$pool{$row[1]}{"max_bytes"}		= $row[11];
	$pool{$row[1]}{"auto_prune"}		= $row[12];
	$pool{$row[1]}{"recycle"}		= $row[13];
	$pool{$row[1]}{"type"}			= $row[14];
	$pool{$row[1]}{"label_format"}		= $row[15];
	$pool{$row[1]}{"enabled"}		= $row[16];
	$pool{$row[1]}{"scratch_pool"}		= $row[17];
	$pool{$row[1]}{"recycle_pool"}		= $row[18];
# }}}

	# Increase number of pool counters
	$pool++;
    }

    return($pool, %pool);
}
# }}}

# {{{ Get media information
sub get_info_media {
    my($QUERY, $media, %media);

    # Setup and execute the SQL query
    $QUERY  = "SELECT * FROM Media";
    my $sth = $dbh->prepare($QUERY) || die("Could not prepare SQL query: $dbh->errstr\n");
    $sth->execute || die("Could not execute query: $sth->errstr\n");

    while( my @row = $sth->fetchrow_array() ) {
	# {{{ Put toghether the pool array
	$media{$row[1]}{"id"}			= $row[0];
	$media{$row[1]}{"slot"}			= $row[2];
	$media{$row[1]}{"pool"}			= $row[3];
	$media{$row[1]}{"type"}			= $row[4];
	$media{$row[1]}{"first_written"}	= $row[5];
	$media{$row[1]}{"last_written"}		= $row[6];
	$media{$row[1]}{"label_date"}		= $row[7];
	$media{$row[1]}{"jobs"}			= $row[8];
	$media{$row[1]}{"files"}		= $row[9];
	$media{$row[1]}{"blocks"}		= $row[10];
	$media{$row[1]}{"mounts"}		= $row[11];
	$media{$row[1]}{"bytes"}		= $row[12];
	$media{$row[1]}{"errors"}		= $row[13];
	$media{$row[1]}{"writes"}		= $row[14];
	$media{$row[1]}{"capacity"}		= $row[15];
	$media{$row[1]}{"status"}		= $row[16];
	$media{$row[1]}{"recycle"}		= $row[17];
	$media{$row[1]}{"retention"}		= $row[18];
	$media{$row[1]}{"use_duration"}		= $row[19];
	$media{$row[1]}{"max_jobs"}		= $row[20];
	$media{$row[1]}{"max_files"}		= $row[21];
	$media{$row[1]}{"max_bytes"}		= $row[22];
	$media{$row[1]}{"in_changer"}		= $row[23];
	$media{$row[1]}{"media_addressing"}	= $row[24];
	$media{$row[1]}{"read_time"}		= $row[25];
	$media{$row[1]}{"write_time"}		= $row[26];
	$media{$row[1]}{"end_file"}		= $row[27];
	$media{$row[1]}{"end_block"}		= $row[28];
# }}}

	# Increase number of media counters
	$media++;
    }

    return($media, %media);
}
# }}}

# {{{ Get job statistics
sub get_info_stats {
    my($QUERY, $status, %status);

    # {{{ Setup and execute the SQL query
    $QUERY  = 'SELECT Job.JobId AS JobNr, Client.Name AS ClientName, Job.Name as JobName, Job.Job AS JobID, Job.JobStatus AS Status, Job.Level AS Level, ';
    $QUERY .= 'Job.StartTime AS StartTime, Job.EndTime AS EndTime, Job.JobFiles AS Files,Job.JobBytes as Bytes, Job.JobErrors AS Errors, ';
    $QUERY .= 'Job.JobMissingFiles AS MissingFiles FROM Client,Job WHERE Job.JobErrors=0 AND Client.ClientId=Job.ClientId AND Job.Type="B"'; 
    $QUERY .= 'ORDER BY ClientName, JobName, JobID, JobNr';
    my $sth = $dbh->prepare($QUERY) || die("Could not prepare SQL query: $dbh->errstr\n");
    $sth->execute || die("Could not execute query: $sth->errstr\n");
# }}}

    while( my @row = $sth->fetchrow_array() ) {
	# row[0]:  JobNr	1512
	# row[1]:  ClientName	aurora.bayour.com-fd
	# row[2]:  JobName	Aurora_System
	# row[3]:  JobID	Aurora_System.2005-09-22_03.00.01
	# row[4]:  Status	T					=> A, R, T or f
	# row[5]:  Level	I					=> D, F or I
	# row[6]:  StartTime	2005-09-22 09:39:04
	# row[7]:  EndTime	2005-09-22 10:12:10
	# row[8]:  Files	1133
	# row[9]:  Bytes	349069751
	# row[10]: Errors	0
	# row[11]: MissingFiles	0

	# {{{ Extract date and time
	my ($start_date, $start_time) = split(' ', $row[6]);
	my ($end_date,   $end_time)   = split(' ', $row[7]);
# }}}

	# Calculate how long the job took
	my $duration = calculate_duration($start_date, $start_time, $end_date, $end_time);

	# {{{ Convert a '2005-09-22 09:39:04' date/time string to '20050922093904Z'
	my $start = $start_date." ".$start_time;
	$start =~ s/\-//g; $start =~ s/\ //g; $start =~ s/://g; $start .= "Z";
	
	my $end   = $end_date." ".$end_time;
	$end   =~ s/\-//g; $end   =~ s/\ //g; $end   =~ s/://g; $end   .= "Z";
# }}}
		
	# {{{ Put toghether the status array.
	$status{$row[1]}{$row[2]}{$row[3]}{"jobnr"}	 = $row[0];
	$status{$row[1]}{$row[2]}{$row[3]}{"status"}	 = $row[4];
	$status{$row[1]}{$row[2]}{$row[3]}{"level"}	 = $row[5];
	$status{$row[1]}{$row[2]}{$row[3]}{"start_date"} = $start;
	$status{$row[1]}{$row[2]}{$row[3]}{"end_date"}   = $end;
	$status{$row[1]}{$row[2]}{$row[3]}{"files"}      = $row[8];
	$status{$row[1]}{$row[2]}{$row[3]}{"bytes"}      = $row[9];
	$status{$row[1]}{$row[2]}{$row[3]}{"errors"}	 = $row[10];
	$status{$row[1]}{$row[2]}{$row[3]}{"missing"}	 = $row[11];
	$status{$row[1]}{$row[2]}{$row[3]}{"duration"}   = $duration;
# }}}

	$status++; # Increase number of status counters
    }

    return($status, %status);
}
# }}}

# {{{ Get next value from a set of input
sub get_next_oid {
    my @tmp = @_;

    &output_extra_debugging(@tmp) if($CFG{'DEBUG'} > 3);

    # next1 => Base OID to use in call
    # next2 => next1.next2 => Full OID to retreive
    # next3 => Client number (OID_BASE.4) or Job ID (OID_BASE.7)
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
	    $TYPE_STATUS = $tmp[2];
	    $CLIENT_NO   = $tmp[3];
	    $JOB_NO      = $tmp[4];
	} elsif($tmp[2] >= 4) {
	    # Statistic counters
	    $TYPE_STATUS = $tmp[2] - 3; # Offset three because of index etc.
	    $CLIENT_NO   = $tmp[3];
	    $JOB_NO      = $tmp[4];
	}
    } else {
	$CLIENT_NO   = $tmp[3];
	$TYPE_STATUS = $tmp[4];
    }

    my $string;
    $string  = "STATUS_TYPE=$TYPE_STATUS" if(defined($TYPE_STATUS));
    $string .= ", " if($string);
    $string .= "CLIENT_NO=$CLIENT_NO" if(defined($CLIENT_NO));
    $string .= ", " if($string);
    $string .= "JOB_NO=$JOB_NO" if(defined($JOB_NO));

    &echo(0, "=> get_next_oid(): $string\n") if($CFG{'DEBUG'} > 2);
    return($next1, $next2, $next3);
}
# }}}


# ====================================================
# =====       P R I N T  F U N C T I O N S       =====

# {{{ OID_BASE.1.0		Output total number of client counters
sub print_amount_clients {
    if($CFG{'DEBUG'}) {
	&echo(0, "=> OID_BASE.totalClients.0\n") if($CFG{'DEBUG'} > 1);
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
    if($CFG{'DEBUG'}) {
	&echo(0, "=> OID_BASE.totalTypes.0\n") if($CFG{'DEBUG'} > 1);
	&echo(0, "$OID_BASE.2.0 $TYPES_STATS\n");
    }

    &echo(1, "$OID_BASE.2.0\n");
    &echo(1, "integer\n");
    &echo(1, "$TYPES_STATS\n");

    return 1;
}
# }}}

# {{{ OID_BASE.3.0		Output total number of statistic counters
sub print_amount_stats {
    if($CFG{'DEBUG'}) {
	&echo(0, "=> OID_BASE.totalStats.0\n") if($CFG{'DEBUG'} > 1);
	&echo(0, "$OID_BASE.3.0 $STATUS\n");
    }

    &echo(1, "$OID_BASE.3.0\n");
    &echo(1, "integer\n");
    &echo(1, "$STATUS\n");

    return 1;
}
# }}}

# {{{ OID_BASE.4.0		Output total number of pools
sub print_amount_pools {
    if($CFG{'DEBUG'}) {
	&echo(0, "=> OID_BASE.totalPools.0\n") if($CFG{'DEBUG'} > 1);
	&echo(0, "$OID_BASE.4.0 $POOLS\n");
    }

    &echo(1, "$OID_BASE.4.0\n");
    &echo(1, "integer\n");
    &echo(1, "$POOLS\n");

    return 1;
}
# }}}

# {{{ OID_BASE.5.0		Output total number of pools
sub print_amount_medias {
    if($CFG{'DEBUG'}) {
	&echo(0, "=> OID_BASE.totalMedias.0\n") if($CFG{'DEBUG'} > 1);
	&echo(0, "$OID_BASE.5.0 $MEDIAS\n");
    }

    &echo(1, "$OID_BASE.5.0\n");
    &echo(1, "integer\n");
    &echo(1, "$MEDIAS\n");

    return 1;
}
# }}}


# {{{ OID_BASE.6.1.1.x		Output client index
sub print_clients_index {
    my $client_no = shift; # Client number
    my($i, $max);
    my $success = 0;
    &echo(0, "=> OID_BASE.clientTable.clientEntry.IndexClients\n") if($CFG{'DEBUG'} > 1);

    if(defined($client_no)) {
	# {{{ Specific client index
	if(!$CLIENTS[$client_no]) {
	    &echo(0, "=> No value in this object ($client_no)\n") if($CFG{'DEBUG'});
	    return 0;
	}
    
	$i = $client_no;
	$max = $client_no;
# }}}
    } else {
	# {{{ The FULL client index
	$i = 1;
	$max = $TYPES_CLIENT;
# }}}
    }

    # {{{ Output index
    for(; $i <= $max; $i++) {
	&echo(0, "$OID_BASE.6.1.1.$i $i\n") if($CFG{'DEBUG'});

	&echo(1, "$OID_BASE.6.1.1.$i\n");
	&echo(1, "integer\n");
	&echo(1, "$i\n");

	$success = 1;
    }
# }}}

    return $success;
}
# }}}

# {{{ OID_BASE.6.1.2.x		Output client counter
sub print_clients_counter {
    my $client_no = shift; # Client number
    my $success = 0;
    &echo(0, "=> OID_BASE.clientTable.clientEntry.clientCounter\n") if($CFG{'DEBUG'} > 1);

    if(defined($client_no)) {
	# {{{ Specific client index
	my $key_counter = 1;
	foreach my $key_nr (sort keys %keys_client) {
	    if($key_nr == $key_counter) {
		my $key_name = $keys_client{$key_nr};

		&echo(0, "$OID_BASE.6.1.2.$key_nr $key_name\n") if($CFG{'DEBUG'});
		
		&echo(1, "$OID_BASE.6.1.2.$key_nr\n");
		&echo(1, "integer\n");
		&echo(1, "$key_name\n");
		
		$success = 1;
	    }

	    $key_counter++;
	}	
# }}}
    } else {
	# {{{ The FULL client index
	foreach my $key_nr (sort keys %keys_client) {
	    my $key_name = $keys_client{$key_nr};

	    &echo(0, "$OID_BASE.6.1.2.$key_nr $key_name\n") if($CFG{'DEBUG'});
	    
	    &echo(1, "$OID_BASE.6.1.2.$key_nr\n");
	    &echo(1, "integer\n");
	    &echo(1, "$key_name\n");
	    
	    $success = 1;
	}
# }}}
    }

    return $success;
}
# }}}

# {{{ OID_BASE.6.1.3.x		Output client name
sub print_clients_name {
    my $client_no = shift; # Client number

    if(defined($client_no)) {
	# {{{ Specific client name
	foreach my $key_nr (sort keys %keys_client) {
	    if($key_nr == $TYPE_CLIENT) {
		my $key_name = $keys_client{$key_nr};
		
		my $client_nr = 1;
		&echo(0, "=> OID_BASE.clientTable.clientEntry.$key_name.clientName\n") if($CFG{'DEBUG'} > 1);
		foreach my $client_name (sort keys %CLIENTS) {
		    if($client_nr == $client_no) {
			&echo(0, "$OID_BASE.6.1.3.$key_nr.$client_nr ".$CLIENTS{$client_name}{$key_name}."\n") if($CFG{'DEBUG'});
			
			&echo(1, "$OID_BASE.6.1.3.$key_nr.$client_nr\n");
			&echo(1, "string\n");
			&echo(1, $CLIENTS{$client_name}{$key_name}."\n");
			
		    }

		    $client_nr++;
		}
	    }
	}	
# }}}
    } else {
	# {{{ ALL client names
	foreach my $key_nr (sort keys %keys_client) {
	    my $key_name = $keys_client{$key_nr};
	    
	    my $client_nr = 1;
	    &echo(0, "=> OID_BASE.clientTable.clientEntry.$key_name.clientName\n") if($CFG{'DEBUG'} > 1);
	    foreach my $client_name (sort keys %CLIENTS) {
		&echo(0, "$OID_BASE.6.1.3.$key_nr.$client_nr ".$CLIENTS{$client_name}{$key_name}."\n") if($CFG{'DEBUG'});
		
		&echo(1, "$OID_BASE.6.1.3.$key_nr.$client_nr\n");
		&echo(1, "string\n");
		&echo(1, $CLIENTS{$client_name}{$key_name}."\n");
		
		$client_nr++;
	    }
	}
# }}}
    }

    return 1;
}
# }}}


# {{{ OID_BASE.7.1.1.a		Output job status index
sub print_types_index {
    my $key_nr = shift;
    my $success = 0;
    my($i, $max);

    &echo(0, "=> OID_BASE.statsTable.statsEntry.IndexStats\n") if($CFG{'DEBUG'} > 1);
    if(defined($key_nr)) {
	# {{{ One specific status index number
	if(!$keys_stats{$key_nr}) {
	    &echo(0, "=> No such status type ($key_nr)\n") if($CFG{'DEBUG'} > 1);
	    return 0;
	}

	$i = $key_nr;
	$max = $key_nr;
# }}}
    } else {
	# {{{ ALL status indexes
	$i = 1;
	$max = $TYPES_STATS;
# }}}
    }

    # {{{ Output index
    for(; $i <= $max; $i++) {
	my $key_name = $keys_stats{$i};
	
	&echo(0, "$OID_BASE.7.1.1.$i $i\n") if($CFG{'DEBUG'});
	
	&echo(1, "$OID_BASE.7.1.1.$i\n");
	&echo(1, "integer\n");
	&echo(1, "$i\n");
	
	$success = 1;
    }
# }}}

    return $success;
}
# }}}

# {{{ OID_BASE.7.1.2.a		Output the types
sub print_types_names {
    my $key_nr = shift;
    my $success = 0;
    my($i, $max);

    &echo(0, "=> OID_BASE.statsTable.statsEntry.statsTypeName\n") if($CFG{'DEBUG'} > 1);
    if(defined($key_nr)) {
	# {{{ One specific type name
	if(!$keys_stats{$key_nr}) {
	    &echo(0, "=> No such status type ($key_nr)\n") if($CFG{'DEBUG'} > 1);
	    return 0;
	}

	$i = $key_nr;
	$max = $key_nr;
# }}}
    } else {
	# {{{ ALL status indexes
	$i = 1;
	$max = $TYPES_STATS;
# }}}
    }

    # {{{ Output index
    for(; $i <= $max; $i++) {
	my $key_name = $keys_stats{$i};
	
	&echo(0, "$OID_BASE.7.1.2.$i $key_name\n") if($CFG{'DEBUG'});
	
	&echo(1, "$OID_BASE.7.1.2.$i\n");
	&echo(1, "string\n");
	&echo(1, "$key_name\n");
	
	$success = 1;
    }
# }}}

    return $success;
}
# }}}

# {{{ OID_BASE.7.1.3.x.y.z	Output the job ID's
sub print_jobs_ids {
    my $job_name_nr = shift;
    my $success = 0;

    if(defined($CLIENT_NO)) {
	# {{{ Job ID for a specific client and a specific job name
	if(!$CLIENTS[$CLIENT_NO]) {
	    &echo(0, "=> No value in this object\n") if($CFG{'DEBUG'} > 1);
	    return 0;
	}

	&echo(0, "=> OID_BASE.statsTable.statsEntry.clientID.jobID\n") if($CFG{'DEBUG'} > 1);

	# Get client name from the client number (which is a global variable).
	my($client_no, $client_name) = split(';', $CLIENTS[$CLIENT_NO]);

	# Get the job name requested
	my $job_name_num = 1;
	foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
	    if($job_name_num == $JOB_NO) {
		my $job_id_num = 1;
		foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
		    if($job_id_num == $job_name_nr) {
			&echo(0, "$OID_BASE.7.1.3.$client_no.$job_name_num.$job_id_num $job_id\n") if($CFG{'DEBUG'});
			
			&echo(1, "$OID_BASE.7.1.3.$client_no.$job_name_num.$job_id_num\n");
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
	&echo(0, "=> OID_BASE.statsTable.statsEntry.clientID.jobID\n") if($CFG{'DEBUG'} > 1);
	foreach my $client_name (keys %STATUS) {
	    my $job_name_num = 1;
	    &echo(0, "=> Client name: '$client_name'\n") if($CFG{'DEBUG'} > 3);
	    foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
		my $job_id_num = 1;
		&echo(0, "=>   Job name: '$job_name'\n") if($CFG{'DEBUG'} > 3);
		foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
		    &echo(0, "=>     Job ID: '$job_id'\n") if($CFG{'DEBUG'} > 3);

		    &echo(0, "$OID_BASE.7.1.3.$client_name_num.$job_name_num.$job_id_num $job_id\n") if($CFG{'DEBUG'});
		    
		    &echo(1, "$OID_BASE.7.1.3.$client_name_num.$job_name_num.$job_id_num\n");
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

# {{{ OID_BASE.7.1.a.x.y.z	Output job status
sub print_jobs_status {
    my $job_status_nr = shift;
    my $success = 0;

    if(defined($CLIENT_NO)) {
	# {{{ Status for a specific client, specific job ID and a specific type
	if(!$CLIENTS[$CLIENT_NO]) {
	    &echo(0, "=> No value in this object\n") if($CFG{'DEBUG'} > 1);
	    return 0;
	}

	# Get client name from the client number (which is a global variable).
	my($client_no, $client_name) = split(';', $CLIENTS[$CLIENT_NO]);

	# Get the key name from the key number (which is a global variable).
	my $key_name;
	if(!$keys_stats{$TYPE_STATUS}) {
	    &echo(0, "=> No value in this object\n") if($CFG{'DEBUG'} > 1);
	    return 0;
	} else {
	    $key_name = $keys_stats{$TYPE_STATUS};
	}
	my $type = $TYPE_STATUS + 3; # Offset three because of index etc.

	my $i=1; # Job Name
	foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
	    if($i == $JOB_NO) {
		my $j=1; # Job ID

		&echo(0, "=> OID_BASE.statsTable.statsEntry.$key_name.clientId.jobNr\n") if($CFG{'DEBUG'} > 1);
		foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
		    if($j == $job_status_nr) {
			&echo(0, "$OID_BASE.7.1.$type.$client_no.$i.$j ".$STATUS{$client_name}{$job_name}{$job_id}{$key_name}."\n") if($CFG{'DEBUG'});

			&echo(1, "$OID_BASE.7.1.$type.$client_no.$i.$j\n");
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
	foreach my $key_nr (sort keys %keys_stats) {
	    my $key_name = $keys_stats{$key_nr};
	    my $type_nr = $key_nr + 3; # Offset three because of index etc.
	    &echo(0, "=> OID_BASE.statsTable.statsEntry.$key_name.clientId.jobNr\n") if($CFG{'DEBUG'} > 1);

	    my $client_num = 1;
	    foreach my $client_name (keys %STATUS) {
		my $job_name_num = 1;
		foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
		    my $job_id_num = 1;
		    foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
			&echo(0, "$OID_BASE.7.1.$type_nr.$client_num.$job_name_num.$job_id_num ".$STATUS{$client_name}{$job_name}{$job_id}{$key_name}."\n") if($CFG{'DEBUG'});

			&echo(1, "$OID_BASE.7.1.$type_nr.$client_num.$job_name_num.$job_id_num\n");
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


# {{{ OID_BASE.8.1.1.x		Output pool index
sub print_pool_index {
    my $pool_no = shift; # Pool number
    my($i, $max);
    my $success = 0;
    &echo(0, "=> OID_BASE.poolsTable.poolsEntry.IndexPools\n") if($CFG{'DEBUG'} > 1);

    if(defined($pool_no)) {
	# {{{ Specific pool index
	$i = $pool_no;
	$max = $pool_no;
# }}}
    } else {
	# {{{ The FULL pool index
	$i = 1;
	$max = $TYPES_POOL;
# }}}
    }

    # {{{ Output index
    for(; $i <= $max; $i++) {
	&echo(0, "$OID_BASE.8.1.1.$i $i\n") if($CFG{'DEBUG'});

	&echo(1, "$OID_BASE.8.1.1.$i\n");
	&echo(1, "integer\n");
	&echo(1, "$i\n");

	$success = 1;
    }
# }}}

    return $success;
}
# }}}

# {{{ OID_BASE.8.1.2.x		Output pool counter
sub print_pool_counter {
    my $pool_no = shift; # pool number
    my $success = 0;
    &echo(0, "=> OID_BASE.poolTable.poolEntry.poolCounter\n") if($CFG{'DEBUG'} > 1);

    if(defined($pool_no)) {
	# {{{ Specific pool index
	my $key_counter = 1;
	foreach my $key_nr (sort keys %keys_pool) {
	    if($key_nr == $key_counter) {
		my $key_name = $keys_pool{$key_nr};
		$key_nr =~ s/^0//;

		&echo(0, "$OID_BASE.8.1.2.$key_nr $key_name\n") if($CFG{'DEBUG'});
		
		&echo(1, "$OID_BASE.8.1.2.$key_nr\n");
		&echo(1, "integer\n");
		&echo(1, "$key_name\n");
		
		$success = 1;
	    }

	    $key_counter++;
	}	
# }}}
    } else {
	# {{{ The FULL pool index
	foreach my $key_nr (sort keys %keys_pool) {
	    my $key_name = $keys_pool{$key_nr};
	    $key_nr =~ s/^0//;

	    &echo(0, "$OID_BASE.8.1.2.$key_nr $key_name\n") if($CFG{'DEBUG'});
	    
	    &echo(1, "$OID_BASE.8.1.2.$key_nr\n");
	    &echo(1, "integer\n");
	    &echo(1, "$key_name\n");
	    
	    $success = 1;
	}
# }}}
    }

    return $success;
}
# }}}

# {{{ OID_BASE.8.1.3.x		Output pool index
sub print_pool_names {
    my $pool_no = shift; # Pool number

    if(defined($pool_no)) {
	# {{{ Specific pool name
	foreach my $key_nr (sort keys %keys_pool) {
	    if($key_nr == $TYPE_CLIENT) {
		my $key_name = $keys_pool{$key_nr};
		$key_nr =~ s/^0//;
		
		my $pool_nr = 1;
		&echo(0, "=> OID_BASE.poolTable.poolEntry.$key_name.poolName\n") if($CFG{'DEBUG'} > 1);
		foreach my $pool_name (sort keys %POOLS) {
		    if($pool_nr == $pool_no) {
			&echo(0, "$OID_BASE.8.1.3.$key_nr.$pool_nr ".$POOLS{$pool_name}{$key_name}."\n") if($CFG{'DEBUG'});
			
			&echo(1, "$OID_BASE.8.1.3.$key_nr.$pool_nr\n");
			&echo(1, "string\n");
			&echo(1, $POOLS{$pool_name}{$key_name}."\n");
			
		    }

		    $pool_nr++;
		}
	    }
	}	
# }}}
    } else {
	# {{{ ALL pool names
	foreach my $key_nr (sort keys %keys_pool) {
	    my $key_name = $keys_pool{$key_nr};
	    $key_nr =~ s/^0//;
	    
	    my $pool_nr = 1;
	    &echo(0, "=> OID_BASE.poolTable.poolEntry.$key_name.poolName\n") if($CFG{'DEBUG'} > 1);
	    foreach my $pool_name (sort keys %POOLS) {
		&echo(0, "$OID_BASE.6.1.3.$key_nr.$pool_nr ".$POOLS{$pool_name}{$key_name}."\n") if($CFG{'DEBUG'});
		
		&echo(1, "$OID_BASE.6.1.3.$key_nr.$pool_nr\n");
		&echo(1, "string\n");
		&echo(1, $POOLS{$pool_name}{$key_name}."\n");
		
		$pool_nr++;
	    }
	}
# }}}
    }

    return 1;
}
# }}}


# {{{ OID_BASE.9.1.1.x		Output media index
sub print_media_index {
    my $media_no = shift; # Media number
    my($i, $max);
    my $success = 0;
    &echo(0, "=> OID_BASE.mediaTable.mediaEntry.IndexMedia\n") if($CFG{'DEBUG'} > 1);

    if(defined($media_no)) {
	# {{{ Specific media index
	$i = $media_no;
	$max = $media_no;
# }}}
    } else {
	# {{{ The FULL media index
	$i = 1;
	$max = $TYPES_MEDIA;
# }}}
    }

    # {{{ Output index
    for(; $i <= $max; $i++) {
	&echo(0, "$OID_BASE.9.1.1.$i $i\n") if($CFG{'DEBUG'});

	&echo(1, "$OID_BASE.9.1.1.$i\n");
	&echo(1, "integer\n");
	&echo(1, "$i\n");

	$success = 1;
    }
# }}}

    return $success;
}
# }}}

# {{{ OID_BASE.9.1.2.x		Output media counter
sub print_media_counter {
    my $media_no = shift; # Media number
    my $success = 0;
    &echo(0, "=> OID_BASE.mediaTable.meidaEntry.mediaCounter\n") if($CFG{'DEBUG'} > 1);

    if(defined($media_no)) {
	# {{{ Specific media index
	my $key_counter = 1;
	foreach my $key_nr (sort keys %keys_media) {
	    if($key_nr == $key_counter) {
		my $key_name = $keys_media{$key_nr};
		$key_nr =~ s/^0//;

		&echo(0, "$OID_BASE.9.1.2.$key_nr $key_name\n") if($CFG{'DEBUG'});
		
		&echo(1, "$OID_BASE.9.1.2.$key_nr\n");
		&echo(1, "integer\n");
		&echo(1, "$key_name\n");
		
		$success = 1;
	    }

	    $key_counter++;
	}	
# }}}
    } else {
	# {{{ The FULL media index
	foreach my $key_nr (sort keys %keys_media) {
	    my $key_name = $keys_media{$key_nr};
	    $key_nr =~ s/^0//;

	    &echo(0, "$OID_BASE.9.1.2.$key_nr $key_name\n") if($CFG{'DEBUG'});
	    
	    &echo(1, "$OID_BASE.9.1.2.$key_nr\n");
	    &echo(1, "integer\n");
	    &echo(1, "$key_name\n");
	    
	    $success = 1;
	}
# }}}
    }

    return $success;
}
# }}}

# {{{ OID_BASE.9.1.3.x		Output media index
sub print_media_names {
    my $media_no = shift; # Media number

    if(defined($media_no)) {
	# {{{ Specific media name
	foreach my $key_nr (sort keys %keys_media) {
	    if($key_nr == $TYPES_MEDIA) {
		my $key_name = $keys_media{$key_nr};
		$key_nr =~ s/^0//;
		
		my $media_nr = 1;
		&echo(0, "=> OID_BASE.mediaTable.mediaEntry.$key_name.mediaName\n") if($CFG{'DEBUG'} > 1);
		foreach my $media_name (sort keys %MEDIAS) {
		    if($media_nr == $media_no) {
			&echo(0, "$OID_BASE.6.1.3.$key_nr.$media_nr ".$MEDIAS{$media_name}{$key_name}."\n") if($CFG{'DEBUG'});
			
			&echo(1, "$OID_BASE.6.1.3.$key_nr.$media_nr\n");
			&echo(1, "string\n");
			&echo(1, $MEDIAS{$media_name}{$key_name}."\n");
			
		    }

		    $media_nr++;
		}
	    }
	}	
# }}}
    } else {
	# {{{ ALL media names
	foreach my $key_nr (sort keys %keys_media) {
	    my $key_name = $keys_media{$key_nr};
	    $key_nr =~ s/^0//;
	    
	    my $media_nr = 1;
	    &echo(0, "=> OID_BASE.mediaTable.mediaEntry.$key_name.mediaName\n") if($CFG{'DEBUG'} > 1);
	    foreach my $media_name (sort keys %MEDIAS) {
		&echo(0, "$OID_BASE.6.1.3.$key_nr.$media_nr ".$MEDIAS{$media_name}{$key_name}."\n") if($CFG{'DEBUG'});
		
		&echo(1, "$OID_BASE.6.1.3.$key_nr.$media_nr\n");
		&echo(1, "string\n");
		&echo(1, $MEDIAS{$media_name}{$key_name}."\n");
		
		$media_nr++;
	    }
	}
# }}}
    }

    return 1;
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

    exit 1 if($CFG{'DEBUG'});
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

    &echo(0, "=> call_func($func_nr, $func_arg)\n") if($CFG{'DEBUG'} > 2);
    my $func = $functions{$func_nr};
    if($func) {
	$function = "print_".$func;
    } else {
	foreach my $oid (sort keys %functions) {
	    # Take the very first match
	    if($oid =~ /^$func_nr/) {
		&echo(0, "=> '$oid =~ /^$func_nr/'\n") if($CFG{'DEBUG'} > 2);
		$function = "print_".$functions{$oid};
		last;
	    }
	}
    }

    &echo(0, "=> Calling function '$function($func_arg)'\n") if($CFG{'DEBUG'} > 1);
    
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
	&echo(0, "Can't open logfile '/var/log/bacula-snmp-stats.log', $!\n") if($CFG{'DEBUG'});
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
    if($CFG{'DEBUG'}) {
	if(&open_log()) {
	    $log_opened = 1;
	    open(STDERR, ">&LOG") if(($CFG{'DEBUG'} <= 2) || $ENV{'MIBDIRS'});
	}
    }

    if($stdout) {
	print $string;
    } elsif($log_opened) {
	print LOG &get_timestring()," " if($CFG{'DEBUG'} > 2);
	print LOG $string;
    }
}
# }}}

# {{{ Load all information needed
sub load_information {
    # Load configuration file and connect to SQL server.
    &get_config();
    &sql_connect();

    # Get client information
    ($CLIENTS, %CLIENTS) = &get_info_client();

    # Get pool information
    ($POOLS, %POOLS) = &get_info_pool();

    # Get media information
    ($MEDIAS, %MEDIAS) = &get_info_media();

    # Get client name(s), job names, job ID's and all
    # job statistics from the SQL server.
    ($STATUS, %STATUS) = &get_info_stats();

    # Put toghether the CLIENTS array
    my $i = 1;
    foreach my $client_name (keys %STATUS) {
	$CLIENTS[$i] = $i.";".$client_name;
	$i++;
    }

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

&echo(0, "=> OID_BASE => '$OID_BASE'\n") if($CFG{'DEBUG'});

# {{{ Calculate number of base counters and Load information
foreach (keys %keys_stats)  { $TYPES_STATS++;  }
foreach (keys %keys_client) { $TYPES_CLIENT++; }
foreach (keys %keys_pool)   { $TYPES_POOL++;   }
foreach (keys %keys_media)  { $TYPES_MEDIA++;  }

&load_information();
# }}}

# {{{ Go through the argument(s) passed to the program
my $ALL = 0;
for(my $i=0; $ARGV[$i]; $i++) {
    if($ARGV[$i] eq '--help' || $ARGV[$i] eq '-h' || $ARGV[$i] eq '?' ) {
	&help();
    } elsif($ARGV[$i] eq '--debug' || $ARGV[$i] eq '-d') {
	$CFG{'DEBUG'}++;
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
    # {{{ Add the '%keys_stats' array to the '%functions' array
    # First one is already there, so start with the second with value '5'...
    # We do that here instead of at the very top so that output of ALL
    # works without calling print_jobs_status() FIVE times...
    my($i, $j) = (2, 5);
    for(; $keys_stats{$i}; $i++, $j++) {
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
	&echo(0, "=> ARG=$arg\n") if($CFG{'DEBUG'} > 1);

	# Get next line from STDIN -> OID number.
	# $arg == 'getnext' => Get next OID
	# $arg == 'get'     => Get specified OID
	# $arg == 'set'     => Set value for OID
	$oid = <>; chomp($oid);
	$oid =~ s/$OID_BASE//; # Remove the OID base
	$oid =~ s/OID_BASE//;  # Remove the OID base (if we're debugging)
	$oid =~ s/^\.//;       # Remove the first dot if it exists - it's in the way!
	&echo(0, "=> OID=$oid\n") if($CFG{'DEBUG'} > 1);
	
	my @tmp = split('\.', $oid);
	&output_extra_debugging(@tmp) if($CFG{'DEBUG'} > 1);
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
	    } elsif($arg eq 'get') {
		# {{{ Get _this_ OID
		if(!defined($tmp[1])) {
		    &echo(0, "=> No value in this object - exiting!\n") if($CFG{'DEBUG'} > 1);

		    &echo(1, "NONE\n");
		    &echo(0, "\n") if($CFG{'DEBUG'} > 1);
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
		# OID_BASE.6.1.1.x
		# OID_BASE.6.1.2.x
		# OID_BASE.6.1.3.x
		# OID_BASE.6.1.4.x.y
		#
		# OID_BASE.7.1.1.a
		# OID_BASE.7.1.2.a
		# OID_BASE.7.1.a.x.y.z
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
		&echo(0, "=> Get next OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} > 2);
		if(!&call_func($next1, $next3)) {
		    # {{{ Figure out the NEXT value from the input
		    if($tmp[2] >= 3) {
			if($tmp[0] == 4) {
			    # OID_BASE.6
			    $tmp[3]++;
			    $tmp[4] = 1;
			} else {
			    # OID_BASE.7
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
			    # OID_BASE.7
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

		    &echo(0, "=> No OID at that level (-1) - get next branch OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} > 2);
		    if(!&call_func($next1, $next3)) {
			# {{{ Figure out the NEXT value from the input
			if($tmp[0] == 4) {
			    # OID_BASE.6
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

			&echo(0, "=> No OID at that level (-2) - get next branch OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} > 2);
			if(!&call_func($next1, $next3)) {
			    # {{{ Figure out the NEXT value from the input
			    # This should be quite simple. It is only (?) called in the
			    # OID_BASE.7.1.3 branch which is two extra oid levels 'deep'.
			    # Input: OID_BASE.7.1.3.4.9.2
			    #     1: OID_BASE.7.1.3.4.9.3
			    #    -1: OID_BASE.7.1.3.4.10.3
			    #    -2: OID_BASE.7.1.3.5.1.1
			    #    -3: OID_BASE.7.1.4.1.1.1 <- here
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

			    &echo(0, "=> No OID at that level (-3) - get next branch OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} > 2);
			    &call_func($next1, $next3);
			}
		    }
		}
# }}} # Call functions
# }}} # Get _next_ OID
	    } elsif($arg eq 'get' {
		# {{{ Get _this_ OID
		if((($tmp[0] == 4) && (!defined($tmp[1]) || !defined($tmp[2]) || !defined($tmp[3]))) ||
		   (($tmp[0] == 5) && (!defined($tmp[1]) || !defined($tmp[2]))))
		{
		    &echo(0, "=> No value in this object - exiting!\n") if($CFG{'DEBUG'} > 1);

		    &echo(1, "NONE\n");
		    &echo(0, "\n") if($CFG{'DEBUG'} > 1);
		    next;
		} else {
		    # How to call call_func()
		    my($next1, $next2, $next3) = get_next_oid(@tmp);

		    &echo(0, "=> Get this OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} > 2);
		    &call_func($next1, $next3);
		}
# }}} # Get _this_ OID
	    }
# }}} # OID_BASE.[4-5]
	} else {
	    # {{{ ------------------------------------- Unknown OID 
	    &echo(0, "Error: No such OID '$OID_BASE' . '$oid'.\n") if($CFG{'DEBUG'});
	    &echo(0, "\n") if($CFG{'DEBUG'} > 1);
	    next;
# }}} # No such OID
	}

	&echo(0, "\n") if($CFG{'DEBUG'} > 1);
    }
# }}}
}
