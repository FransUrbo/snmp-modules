#!/usr/bin/perl -w

# {{{ $Id: bacula-snmp-stats.pl,v 1.16 2005-11-01 11:01:35 turbo Exp $
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

# {{{ The 'flow' of the OID/MIB tree.
my %functions  = (# baculaTotal*	Total counters
		  $OID_BASE.".01"	=> "amount_clients",
		  $OID_BASE.".02"	=> "amount_stats",
		  $OID_BASE.".03"	=> "amount_pools",
		  $OID_BASE.".04"	=> "amount_medias",

		  # baculaClientsTable	The client information
		  $OID_BASE.".05.1.1"	=> "clients_index",
		  $OID_BASE.".05.1.2"	=> "clients_name",

		  # baculaJobsTable	The job ID information
		  $OID_BASE.".06.1.1"	=> "jobs_names_index",
		  $OID_BASE.".06.1.2"	=> "jobs_names",

		  # baculaJobsTable	The job ID information
		  $OID_BASE.".07.1.1"	=> "jobs_ids_index",
		  $OID_BASE.".07.1.2"	=> "jobs_ids",

		  # baculaStatsCountersTable
		  $OID_BASE.".08.1.1"   => "jobs_status_counters_index",
		  $OID_BASE.".08.1.2"   => "jobs_status_counters",

		  # baculaStatsTable	The status information
		  $OID_BASE.".09.1.1"	=> "jobs_status_index",
		  $OID_BASE.".09.1.2"	=> "jobs_status",

		  # baculaPoolsTable	The pool information
		  $OID_BASE.".10.1.1"	=> "pool_index",
		  $OID_BASE.".10.1.2"	=> "pool_names",

		  # baculaMediaTable	The media information
		  $OID_BASE.".11.1.1"	=> "media_index",
		  $OID_BASE.".11.1.2"	=> "media_names");

# MIB tree 'flow' below the '$OID_BASE.9.3' branch.
my %keys_stats  = (#01  => index
		   "02" => "start_date",
		   "03" => "end_date",
		   "04" => "duration",
		   "05" => "files",
		   "06" => "bytes",
		   "07" => "type",
		   "08" => "status",
		   "09" => "level",
		   "10" => "errors",
		   "11" => "missing");

my %keys_jobs   = (#01  => index
		   "02" => "filesetname",
		   "03" => "filesetdesc",
		   "04" => "md5",
		   "05" => "create_time");

my %keys_client = (#01  => index
		   "02" => "id",
		   "03" => "uname",
		   "04" => "auto_prune",
		   "05" => "file_retention",
		   "06" => "job_retention");

my %keys_pool   = (#01  => index
		   "02" => "id",
		   "03" => "num_vols",
		   "04" => "max_vols",
		   "05" => "use_once",
		   "06" => "use_catalog",
		   "07" => "accept_any_vol",
		   "08" => "vol_retention",
		   "09" => "vol_use_duration",
		   "10" => "max_jobs",
		   "11" => "max_files",
		   "12" => "max_bytes",
		   "13" => "auto_prune",
		   "14" => "recycle",
		   "15" => "type",
		   "16" => "label_format",
		   "17" => "enabled",
		   "18" => "scratch_pool",
		   "19" => "recycle_pool");

my %keys_media  = (#01  => index
		   "02" => "name",
		   "03" => "slot",
		   "04" => "pool",
		   "05" => "type",
		   "06" => "first_written",
		   "07" => "last_written",
		   "08" => "label_date",
		   "09" => "jobs",
		   "10" => "files",
		   "11" => "blocks",
		   "12" => "mounts",
		   "13" => "bytes",
		   "14" => "errors",
		   "15" => "writes",
		   "16" => "capacity",
		   "17" => "status",
		   "18" => "recycle",
		   "19" => "retention",
		   "20" => "use_duration",
		   "21" => "max_jobs",
		   "22" => "max_files",
		   "23" => "max_bytes",
		   "24" => "in_changer",
		   "25" => "media_addressing",
		   "26" => "read_time",
		   "27" => "write_time",
		   "28" => "end_file",
		   "29" => "end_block");
# }}} # Flow

# {{{ Writable entries
my %writables = ($OID_BASE.".5.1.4"   => 'client_autoprune',
		 $OID_BASE.".5.1.5"   => 'client_retentionfile',
		 $OID_BASE.".5.1.6"   => 'client_retentionjob',
		 $OID_BASE.".10.1.5"  => 'pools_useonce',
		 $OID_BASE.".10.1.6"  => 'pools_usecatalog',
		 $OID_BASE.".10.1.7"  => 'pools_acceptanyvolume',
		 $OID_BASE.".10.1.8"  => 'pools_retention',
		 $OID_BASE.".10.1.9"  => 'pools_duration',
		 $OID_BASE.".10.1.10" => 'pools_maxjobs',
		 $OID_BASE.".10.1.11" => 'pools_maxfiles',
		 $OID_BASE.".10.1.12" => 'pools_maxbytes',
		 $OID_BASE.".10.1.13" => 'pools_autoprune',
		 $OID_BASE.".10.1.14" => 'pools_recycle',
		 $OID_BASE.".10.1.15" => 'pools_type',
		 $OID_BASE.".10.1.16" => 'pools_labelformat',
		 $OID_BASE.".10.1.17" => 'pools_enabled');
# }}}

# {{{ Some global data variables
my($oid, %STATUS, %POOLS, %MEDIAS, @CLIENTS, %CLIENTS, %JOBS);

# Total numbers
my($TYPES_STATS, $TYPES_CLIENT, $TYPES_POOL, $TYPES_MEDIA, $TYPES_JOBS);
my($CLIENTS, $JOBS, $STATUS, $POOLS, $MEDIAS);

# Because &print_jobs_name() needs TWO args, not ONE,
# but &call_print() can't handle that and it would be
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
# }}}

# handle a SIGALRM - read information from the SQL server
$SIG{'ALRM'} = \&load_information;
# }}}

# {{{ OID tree
# smidump -f tree BAYOUR-COM-MIB.txt
# +--baculaStats(3)
#    |
#    +-- r-n Integer32 baculaTotalClients(1)
#    +-- r-n Integer32 baculaTotalStats(2)
#    +-- r-n Integer32 baculaTotalPools(3)
#    +-- r-n Integer32 baculaTotalMedia(4)
#    |
#    +--baculaClientsTable(5)
#    |  |
#    |  +--baculaClientsEntry(1) [baculaClientsIndex]
#    |     |
#    |     +-- --- CounterIndex  baculaClientsIndex(1)
#    |     +-- r-n DisplayString baculaClientName(2)
#    |     +-- r-n DisplayString baculaClientUname(3)
#    |     +-- rwn TrueFalse     baculaClientAutoPrune(4)
#    |     +-- rwn Counter32     baculaClientRetentionFile(5)
#    |     +-- rwn Counter32     baculaClientRetentionJob(6)
#    |
#    +--baculaJobsNameTable(6)
#    |  |
#    |  +--baculaJobsNameEntry(1) [baculaClientsIndex,baculaJobsNameIndex]
#    |     |
#    |     +-- --- CounterIndex  baculaJobsNameIndex(1)
#    |     +-- r-n DisplayString baculaJobsName(2)
#    |     +-- r-n DisplayString baculaJobsDesc(3)
#    |     +-- r-n DisplayString baculaJobsMD5(4)
#    |     +-- r-n DisplayString baculaJobsCreate(5)
#    |
#    +--baculaJobsIDTable(7)
#    |  |
#    |  +--baculaJobsIDEntry(1) [baculaClientsIndex,baculaJobsNameIndex,baculaJobsIDIndex]
#    |     |
#    |     +-- --- CounterIndex  baculaJobsIDIndex(1)
#    |     +-- r-n DisplayString baculaJobsID(2)
#    |
#    +--baculaStatsCountersTable(8)
#    |  |
#    |  +--baculaStatsCountersEntry(1) [baculaStatsCountersIndex]
#    |     |
#    |     +-- --- CounterIndex  baculaStatsCountersIndex(1)
#    |     +-- r-n DisplayString baculaStatsCounterName(2)
#    |
#    +--baculaStatsTable(9)
#    |  |
#    |  +--baculaStatsEntry(1) [baculaClientsIndex,baculaJobsNameIndex,baculaJobsIDIndex,baculaStatsIndex]
#    |     |
#    |     +-- --- CounterIndex  baculaStatsIndex(1)
#    |     +-- r-n DisplayString baculaStatsStart(2)
#    |     +-- r-n DisplayString baculaStatsEnd(3)
#    |     +-- r-n Integer32     baculaStatsDuration(4)
#    |     +-- r-n Integer32     baculaStatsFiles(5)
#    |     +-- r-n Counter32     baculaStatsBytes(6)
#    |     +-- r-n DisplayString baculaStatsType(7)
#    |     +-- r-n Status        baculaStatsStatus(8)
#    |     +-- r-n Level         baculaStatsLevel(9)
#    |     +-- r-n Integer32     baculaStatsErrors(10)
#    |     +-- r-n Integer32     baculaStatsMissingFiles(11)
#    |
#    +--baculaPoolsTable(10)
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
#    |     +-- rwn Counter32     baculaPoolsRetention(8)
#    |     +-- rwn Counter32     baculaPoolsDuration(9)
#    |     +-- rwn Integer32     baculaPoolsMaxJobs(10)
#    |     +-- rwn Integer32     baculaPoolsMaxFiles(11)
#    |     +-- rwn Counter32     baculaPoolsMaxBytes(12)
#    |     +-- rwn TrueFalse     baculaPoolsAutoPrune(13)
#    |     +-- rwn TrueFalse     baculaPoolsRecycle(14)
#    |     +-- rwn DisplayString baculaPoolsType(15)
#    |     +-- rwn DisplayString baculaPoolsLabelFormat(16)
#    |     +-- rwn TrueFalse     baculaPoolsEnabled(17)
#    |     +-- r-n Integer32     baculaPoolsScratchPoolID(18)
#    |     +-- r-n Integer32     baculaPoolsRecyclePoolID(19)
#    |
#    +--baculaMediaTable(11)
#       |
#       +--baculaMediaEntry(1) [baculaMediaIndex]
#          |
#          +-- --- CounterIndex  baculaMediaIndex(1)
#          +-- r-n DisplayString baculaMediaName(2)
#          +-- r-n Integer32     baculaMediaSlot(3)
#          +-- r-n Integer32     baculaMediaPool(4)
#          +-- r-n DisplayString baculaMediaType(5)
#          +-- r-n DisplayString baculaMediaWrittenFirst(6)
#          +-- r-n DisplayString baculaMediaWrittenLast(7)
#          +-- r-n DisplayString baculaMediaLabelDate(8)
#          +-- r-n Integer32     baculaMediaJobs(9)
#          +-- r-n Integer32     baculaMediaFiles(10)
#          +-- r-n Integer32     baculaMediaBlocks(11)
#          +-- r-n Integer32     baculaMediaMounts(12)
#          +-- r-n Counter32     baculaMediaBytes(13)
#          +-- r-n Integer32     baculaMediaErrors(14)
#          +-- r-n Integer32     baculaMediaWrites(15)
#          +-- r-n Counter32     baculaMediaCapacity(16)
#          +-- r-n VolumeStatus  baculaMediaStatus(17)
#          +-- r-n TrueFalse     baculaMediaRecycle(18)
#          +-- r-n Counter32     baculaMediaRetention(19)
#          +-- r-n Counter32     baculaMediaDuration(20)
#          +-- r-n Integer32     baculaMediaMaxJobs(21)
#          +-- r-n Integer32     baculaMediaMaxFiles(22)
#          +-- r-n Counter32     baculaMediaMaxBytes(23)
#          +-- r-n TrueFalse     baculaMediaInChanger(24)
#          +-- r-n TrueFalse     baculaMediaMediaAddressing(25)
#          +-- r-n Counter32     baculaMediaReadTime(26)
#          +-- r-n Counter32     baculaMediaWriteTime(27)
#          +-- r-n Integer32     baculaMediaEndFile(28)
#          +-- r-n Integer32     baculaMediaEndBlock(29)
# }}}

# ====================================================
# =====    R E T R E I V E  F U N C T I O N S    =====

# {{{ Load the information needed to connect to the MySQL server.
sub get_config {
    my $option = shift;
    my($line, $key, $value);

    $option = 0 if(!defined($option));

    if(-e "/etc/bacula/.conn_details") {
	open(CFG, "< /etc/bacula/.conn_details") || die("Can't open /etc/bacula/.conn_details, $!");
	while(!eof(CFG)) {
	    $line = <CFG>; chomp($line);
	    ($key, $value) = split('=', $line);

	    if(!$option) {
		# Get all options
		$CFG{$key} = $value;
	    } elsif($option eq $key) {
		# Get only this option
		$CFG{$key} = $value;
	    }
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

    # A debug value from the environment overrides!
    $CFG{'DEBUG'} = $ENV{'DEBUG_BACULA'} if(defined($ENV{'DEBUG_BACULA'}));
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
	$client{$row[1]}{"file_retention"}	= $row[4] / 1024;
	$client{$row[1]}{"job_retention"}	= $row[5] / 1024;
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

    # {{{ Setup and execute the SQL query
    $QUERY  = "SELECT * FROM Pool";
    my $sth = $dbh->prepare($QUERY) || die("Could not prepare SQL query: $dbh->errstr\n");
    $sth->execute || die("Could not execute query: $sth->errstr\n");
# }}}

    while( my @row = $sth->fetchrow_array() ) {
	# {{{ Put toghether the pool array
	$pool{$row[1]}{"id"}			= $row[1];
	$pool{$row[1]}{"num_vols"}		= $row[2];
	$pool{$row[1]}{"max_vols"}		= $row[3];
	$pool{$row[1]}{"use_once"}		= $row[4];
	$pool{$row[1]}{"use_catalog"}		= $row[5];
	$pool{$row[1]}{"accept_any_vol"}	= $row[6];
	$pool{$row[1]}{"vol_retention"}		= $row[7] / 1024;
	$pool{$row[1]}{"vol_use_duration"}	= $row[8] / 1024;
	$pool{$row[1]}{"max_jobs"}		= $row[9];
	$pool{$row[1]}{"max_files"}		= $row[10];
	$pool{$row[1]}{"max_bytes"}		= $row[11] / 1024;
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
	# tmp[0]: MediaId			1
	# tmp[1]: VolumeName			Tape_4
	# tmp[2]: Slot				0
	# tmp[3]: PoolId			1
	# tmp[4]: MediaType			Ultrium1
	# tmp[5]: FirstWritten			2005-08-22 13:53:58
	# tmp[6]: LastWritten			2005-09-10 01:59:34
	# tmp[7]: LabelDate			2005-08-22 15:38:36
	# tmp[8]: VolJobs			51
	# tmp[9]: VolFiles			144
	# tmp[10]: VolBlocks			1649075
	# tmp[11]: VolMounts			13
	# tmp[12]: VolBytes			106383291718
	# tmp[13]: VolErrors			0
	# tmp[14]: VolWrites			6750966
	# tmp[15]: VolCapacityBytes		0
	# tmp[16]: VolStatus			Purged
	# tmp[17]: Recycle			1
	# tmp[18]: VolRetention			604800
	# tmp[19]: VolUseDuration		0
	# tmp[20]: MaxVolJobs			0
	# tmp[21]: MaxVolFiles			0
	# tmp[22]: MaxVolBytes			0
	# tmp[23]: InChanger			0
	# tmp[24]: MediaAddressing		0
	# tmp[25]: VolReadTime			0
	# tmp[26]: VolWriteTime			0
	# tmp[27]: EndFile			143
	# tmp[28]: EndBlock			2241

	$media{$row[1]}{"name"}			= $row[1];
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
	$media{$row[1]}{"bytes"}		= $row[12] / 1024;
	$media{$row[1]}{"errors"}		= $row[13];
	$media{$row[1]}{"writes"}		= $row[14];
	$media{$row[1]}{"capacity"}		= $row[15] / 1024;
	$media{$row[1]}{"status"}		= $row[16];
	$media{$row[1]}{"recycle"}		= $row[17];
	$media{$row[1]}{"retention"}		= $row[18] / 1024;
	$media{$row[1]}{"use_duration"}		= $row[19] / 1024;
	$media{$row[1]}{"max_jobs"}		= $row[20];
	$media{$row[1]}{"max_files"}		= $row[21];
	$media{$row[1]}{"max_bytes"}		= $row[22] / 1024;
	$media{$row[1]}{"in_changer"}		= $row[23];
	$media{$row[1]}{"media_addressing"}	= $row[24];
	$media{$row[1]}{"read_time"}		= $row[25] / 1024;
	$media{$row[1]}{"write_time"}		= $row[26] / 1024;
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
    $status = 0;

    # {{{ Setup and execute the SQL query
    $QUERY  = 'SELECT Job.JobId AS JobNr, Client.Name AS ClientName, Job.Name AS JobName, Job.Type AS Type, Job.FileSetId AS FileSet, ';
    $QUERY .= 'Job.Job AS JobID, Job.JobStatus AS Status, Job.Level AS Level, Job.StartTime AS StartTime, Job.EndTime AS EndTime, ';
    $QUERY .= 'Job.JobFiles AS Files, Job.JobBytes AS Bytes, Job.JobErrors AS Errors, Job.JobMissingFiles AS MissingFiles FROM Client,Job ';
    $QUERY .= 'WHERE Job.JobErrors=0 AND Client.ClientId=Job.ClientId AND Job.Type="B" ORDER BY ClientName, JobName, JobID, JobNr';
    my $sth = $dbh->prepare($QUERY) || die("Could not prepare SQL query: $dbh->errstr\n");
    $sth->execute || die("Could not execute query: $sth->errstr\n");
# }}}

    while( my @row = $sth->fetchrow_array() ) {
	# row[0]:  JobNr	1512
	# row[1]:  ClientName	aurora.bayour.com-fd
	# row[2]:  JobName	Aurora_System
	# row[3]:  Type		B
	# row[4]:  FileSet	10
	# row[5]:  JobID	Aurora_System.2005-09-22_03.00.01
	# row[6]:  Status	T					=> A, R, T or f
	# row[7]:  Level	I					=> D, F or I
	# row[8]:  StartTime	2005-09-22 09:39:04
	# row[9]:  EndTime	2005-09-22 10:12:10
	# row[10]: Files	1133
	# row[11]: Bytes	349069751
	# row[12]: Errors	0
	# row[13]: MissingFiles	0

	if($CFG{'DEBUG'} > 4) {
	    my $tmp = join(':', @row);
	    &echo(0, "ROW[$status]: '$tmp'\n");
	}

	# {{{ Extract date and time
	my ($start_date, $start_time) = split(' ', $row[8]);
	my ($end_date,   $end_time)   = split(' ', $row[9]);

	$row[8] = '' if($row[7] eq '0000-00-00 00:00:00');
	$row[9] = '' if($row[8] eq '0000-00-00 00:00:00');
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
	$status{$row[1]}{$row[2]}{$row[5]}{"jobnr"}	 = $row[0];
	$status{$row[1]}{$row[2]}{$row[5]}{"type"}	 = $row[3];
	$status{$row[1]}{$row[2]}{$row[5]}{"fileset"}	 = $row[4];
	$status{$row[1]}{$row[2]}{$row[5]}{"status"}	 = $row[6];
	$status{$row[1]}{$row[2]}{$row[5]}{"level"}	 = $row[7];
	$status{$row[1]}{$row[2]}{$row[5]}{"start_date"} = $row[8];
	$status{$row[1]}{$row[2]}{$row[5]}{"end_date"}   = $row[9];
	$status{$row[1]}{$row[2]}{$row[5]}{"files"}      = $row[10];
	$status{$row[1]}{$row[2]}{$row[5]}{"bytes"}      = $row[11] / 1024;
	$status{$row[1]}{$row[2]}{$row[5]}{"errors"}	 = $row[12];
	$status{$row[1]}{$row[2]}{$row[5]}{"missing"}	 = $row[13];
	$status{$row[1]}{$row[2]}{$row[5]}{"duration"}   = $duration;
# }}}

	$status++; # Increase number of status counters
    }

    &echo(0, "=> Number of status counters: $status\n") if($CFG{'DEBUG'} >= 4);
    return($status, %status);
}
# }}}

# {{{ Get job information
sub get_info_jobs {
    my($jobs, %jobs, %tmp);

    # {{{ Extract all the uniq FileSetID's from the status array
    foreach my $client_name (sort keys %CLIENTS) {
	foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
	    foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
		if(!defined($tmp{$client_name}{$job_name}{"filesetid"})) {
		    $tmp{$client_name}{$job_name}{"filesetid"}   = $STATUS{$client_name}{$job_name}{$job_id}{"fileset"};
		    $tmp{$client_name}{$job_name}{"filesetname"} = $job_name;
		}
	    }
	}
    }
# }}}

    # {{{ Retreive file set information from SQL
    foreach my $client_name (sort keys %tmp) {
	foreach my $job_name (sort keys %{ $tmp{$client_name} }) {
	    # Setup and execute the SQL query
	    my $QUERY = 'SELECT * FROM FileSet WHERE FileSetId="'.$tmp{$client_name}{$job_name}{"filesetid"}.'"';
	    my $sth = $dbh->prepare($QUERY) || die("Could not prepare SQL query: $dbh->errstr\n");
	    $sth->execute || die("Could not execute query: $sth->errstr\n");
	    
	    # Retreive the row (there should be only one match!)
	    my @row = $sth->fetchrow_array();
	    # row[0]: FileSetId
	    # row[1]: FileSet(desc)
	    # row[2]: MD5
	    # row[3]: Createtime
	    
	    if($row[0]) {
		# Put toghether the jobs array
		$jobs{$client_name}{$job_name}{"filesetname"} = $tmp{$client_name}{$job_name}{"filesetname"};
		$jobs{$client_name}{$job_name}{"filesetdesc"} = $row[1];
		$jobs{$client_name}{$job_name}{"md5"}         = $row[2];
		$jobs{$client_name}{$job_name}{"create_time"} = $row[3];
	    } else {
		$jobs{$client_name}{$job_name}{"filesetname"} = $tmp{$client_name}{$job_name}{"filesetname"};
		$jobs{$client_name}{$job_name}{"filesetdesc"} = '';
		$jobs{$client_name}{$job_name}{"md5"}         = '';
		$jobs{$client_name}{$job_name}{"create_time"} = '';
	    }

	    $jobs++; # Increase number of job information records
	}
    }
# }}}

    return($jobs, %jobs);
}
# }}}


# ====================================================
# =====       P R I N T  F U N C T I O N S       =====

# {{{ OID_BASE.1.0		Output total number of clients
sub print_amount_clients {
    if($CFG{'DEBUG'}) {
	&echo(0, "=> OID_BASE.totalClients.0\n") if($CFG{'DEBUG'} > 1);
	&echo(0, "$OID_BASE.1.0 = $CLIENTS\n");
    }

    &echo(1, "$OID_BASE.1.0\n");
    &echo(1, "integer\n");
    &echo(1, "$CLIENTS\n");

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return 1;
}
# }}}

# {{{ OID_BASE.2.0		Output total number of statistics
sub print_amount_stats {
    if($CFG{'DEBUG'}) {
	&echo(0, "=> OID_BASE.totalStats.0\n") if($CFG{'DEBUG'} > 1);
	&echo(0, "$OID_BASE.2.0 = $STATUS\n");
    }

    &echo(1, "$OID_BASE.2.0\n");
    &echo(1, "integer\n");
    &echo(1, "$STATUS\n");

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return 1;
}
# }}}

# {{{ OID_BASE.3.0		Output total number of pools
sub print_amount_pools {
    if($CFG{'DEBUG'}) {
	&echo(0, "=> OID_BASE.totalPools.0\n") if($CFG{'DEBUG'} > 1);
	&echo(0, "$OID_BASE.3.0 = $POOLS\n");
    }

    &echo(1, "$OID_BASE.3.0\n");
    &echo(1, "integer\n");
    &echo(1, "$POOLS\n");

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return 1;
}
# }}}

# {{{ OID_BASE.4.0		Output total number of pools
sub print_amount_medias {
    if($CFG{'DEBUG'}) {
	&echo(0, "=> OID_BASE.totalMedias.0\n") if($CFG{'DEBUG'} > 1);
	&echo(0, "$OID_BASE.4.0 = $MEDIAS\n");
    }

    &echo(1, "$OID_BASE.4.0\n");
    &echo(1, "integer\n");
    &echo(1, "$MEDIAS\n");

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return 1;
}
# }}}


# {{{ OID_BASE.5.1.1.x		Output client name index
sub print_clients_index {
    my $client_no = shift; # Client number
    my $success = 0;
    &echo(0, "=> OID_BASE.clientTable.clientEntry.IndexClients\n") if($CFG{'DEBUG'} > 1);

    if(defined($client_no)) {
	# {{{ Specific client name
	foreach my $key_nr (sort keys %keys_client) {
	    my $value = sprintf("%02d", $TYPE_STATUS+1); # This is the index - offset one!
	    if($key_nr == $value) {
		my $key_name = $keys_client{$key_nr};
		$key_nr =~ s/^0//;
		$key_nr -= 1; # This is the index - offset one!
		&echo(0, "=> OID_BASE.clientTable.clientEntry.$key_name.clientName\n") if($CFG{'DEBUG'} > 1);
		
		my $client_nr = 1;
		foreach my $client_name (sort keys %CLIENTS) {
		    if($client_nr == $client_no) {
			&echo(0, "$OID_BASE.5.1.$key_nr.$client_nr = $client_nr\n") if($CFG{'DEBUG'});
			
			&echo(1, "$OID_BASE.5.1.$key_nr.$client_nr\n");
			&echo(1, "integer\n");
			&echo(1, "$client_nr\n");
			
			$success = 1;
		    }

		    $client_nr++;
		}
	    }
	}
# }}}
    } else {
	# {{{ ALL client names
	my $client_nr = 1;
	foreach my $client_name (sort keys %CLIENTS) {
	    &echo(0, "$OID_BASE.5.1.1.$client_nr = $client_nr\n") if($CFG{'DEBUG'});
	    
	    &echo(1, "$OID_BASE.5.1.1..$client_nr\n");
	    &echo(1, "integer\n");
	    &echo(1, "$client_nr\n");
	    
	    $success = 1;
	    $client_nr++;
	}
# }}}
    }

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return $success;
}
# }}}

# {{{ OID_BASE.5.1.X.x		Output client name
sub print_clients_name {
    my $value_no = shift; # Value number
    my $success = 0;

    if(defined($value_no)) {
	# {{{ Specific client name
	foreach my $key_nr (sort keys %keys_client) {
	    my $value = sprintf("%02d", $TYPE_STATUS);
	    if($key_nr == $value) {
		my $key_name = $keys_client{$key_nr};
		$key_nr =~ s/^0//;
		&echo(0, "=> OID_BASE.clientTable.clientEntry.$key_name.clientName\n") if($CFG{'DEBUG'} > 1);
		
		my $client_nr = 1;
		foreach my $client_name (sort keys %CLIENTS) {
		    if($client_nr == $value_no) {
			&echo(0, "$OID_BASE.5.1.$key_nr.$client_nr = ".$CLIENTS{$client_name}{$key_name}."\n") if($CFG{'DEBUG'});
			
			&echo(1, "$OID_BASE.5.1.$key_nr.$client_nr\n");
			if($key_name eq 'auto_prune') {
			    &echo(1, "integer\n");
			} elsif(($key_name eq 'file_retention') || ($key_name eq 'job_retention')) {
			    &echo(1, "counter\n");
			} else {
			    &echo(1, "string\n");
			}
			&echo(1, $CLIENTS{$client_name}{$key_name}."\n");
			
			$success = 1;
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
	    $key_nr =~ s/^0//;
	    &echo(0, "=> OID_BASE.clientTable.clientEntry.$key_name.clientName\n") if($CFG{'DEBUG'} > 1);
	    
	    my $client_nr = 1;
	    foreach my $client_name (sort keys %CLIENTS) {
		&echo(0, "$OID_BASE.5.1.$key_nr.$client_nr = ".$CLIENTS{$client_name}{$key_name}."\n") if($CFG{'DEBUG'});
		
		&echo(1, "$OID_BASE.5.1.$key_nr.$client_nr\n");
		if($key_name eq 'auto_prune') {
		    &echo(1, "integer\n");
		} elsif(($key_name eq 'file_retention') || ($key_name eq 'job_retention')) {
		    &echo(1, "counter\n");
		} else {
		    &echo(1, "string\n");
		}
		&echo(1, $CLIENTS{$client_name}{$key_name}."\n");

		$success = 1;
		$client_nr++;
	    }

	    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
	}
# }}}
    }

    return $success;
}
# }}}


# {{{ OID_BASE.6.1.1.x.y	Output the job name index
sub print_jobs_names_index {
    my $job_no = shift; # Job number
    my $success = 0;

    if(defined($job_no)) {
	# {{{ Specific client name
	my $client_name_num = 1;
	&echo(0, "=> OID_BASE.jobsNameTable.jobsNameEntry.IndexJobNames\n") if($CFG{'DEBUG'} > 1);
	foreach my $client_name (sort keys %JOBS) {
	    if($client_name_num == $CLIENT_NO) {
		my $job_name_num = 1;
		foreach my $job_name (sort keys %{ $JOBS{$client_name} }) {
		    if($job_name_num == $job_no) {
			&echo(0, "$OID_BASE.6.1.1.$client_name_num.$job_name_num = $job_name_num\n") if($CFG{'DEBUG'});
			
			&echo(1, "$OID_BASE.6.1.1.$client_name_num.$job_name_num\n");
			&echo(1, "integer\n");
			&echo(1, "$job_name_num\n");
			
			$success = 1;
		    }
		    $job_name_num++;
		}
	    }
	    
	    $client_name_num++;
	}
# }}}
    } else {
	# {{{ ALL clients, all job status
	my $client_name_num = 1;
	&echo(0, "=> OID_BASE.jobsNameTable.jobsNameEntry.clientName.IndexJobNames\n") if($CFG{'DEBUG'} > 1);
	foreach my $client_name (sort keys %JOBS) {
	    my $job_name_num = 1;
	    foreach my $job_name (sort keys %{ $JOBS{$client_name} }) {
		&echo(0, "$OID_BASE.6.1.1.$client_name_num.$job_name_num = $job_name_num\n") if($CFG{'DEBUG'});
		
		&echo(1, "$OID_BASE.6.1.1.$client_name_num.$job_name_num\n");
		&echo(1, "integer\n");
		&echo(1, "$job_name_num\n");
		
		$success = 1;
		$job_name_num++;
	    }
	    
	    $client_name_num++;
	}
# }}}
    }

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return $success;
}
# }}}

# {{{ OID_BASE.6.1.X.x.y	Output the job names
sub print_jobs_names {
    my $job_no = shift; # Job number
    my $success = 0;

    if(defined($job_no)) {
	# {{{ Specific job information
	foreach my $key_nr (sort keys %keys_jobs) {
	    my $value = sprintf("%02d", $TYPE_STATUS);
	    if($key_nr == $value) {
		my $key_name = $keys_jobs{$key_nr};
		$key_nr =~ s/^0//;
		
		&echo(0, "=> OID_BASE.jobsNameTable.jobsNameEntry.$key_name.clientName.jobName\n") if($CFG{'DEBUG'} > 1);
		
		my $client_name_num = 1;
		foreach my $client_name (sort keys %JOBS) {
		    if($client_name_num == $CLIENT_NO) {
			my $job_name_num = 1;
			foreach my $job_name (sort keys %{ $JOBS{$client_name} }) {
			    if($job_name_num == $job_no) {
				&echo(0, "$OID_BASE.6.1.$key_nr.$client_name_num.$job_name_num = ".$JOBS{$client_name}{$job_name}{$key_name}."\n") if($CFG{'DEBUG'});
				
				&echo(1, "$OID_BASE.6.1.$key_nr.$client_name_num.$job_name_num\n");
				if($key_nr == 5) {
				    &echo(1, "string\n");
				} else {
				    &echo(1, "string\n");
				}
				&echo(1, $JOBS{$client_name}{$job_name}{$key_name}."\n");
				
				$success = 1;
			    }

			    $job_name_num++;
			}
		    }

		    $client_name_num++;
		}
	    }
	}
# }}}
    } else {
	# {{{ ALL job information
	foreach my $key_nr (sort keys %keys_jobs) {
	    my $key_name = $keys_jobs{$key_nr};
	    $key_nr =~ s/^0//;

	    &echo(0, "=> OID_BASE.jobsNameTable.jobsNameEntry.$key_name.clientName.jobName\n") if($CFG{'DEBUG'} > 1);

	    my $client_name_num = 1;
	    foreach my $client_name (sort keys %JOBS) {
		my $job_name_num = 1;
		foreach my $job_name (sort keys %{ $JOBS{$client_name} }) {
		    &echo(0, "$OID_BASE.6.1.$key_nr.$client_name_num.$job_name_num = ".$JOBS{$client_name}{$job_name}{$key_name}."\n") if($CFG{'DEBUG'});
		    
		    &echo(1, "$OID_BASE.6.1.$key_nr.$client_name_num.$job_name_num\n");
		    &echo(1, "string\n");
		    &echo(1, "$job_name\n");
		    
		    $success = 1;
		    $job_name_num++;
		}
		
		$client_name_num++;
	    }

	    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
	}
# }}}
    }

    return $success;
}
# }}}


# {{{ OID_BASE.7.1.1.x.y.z	Output the job ID index
sub print_jobs_ids_index {
    my $job_id_no = shift; # Job ID number
    my $success = 0;

    if(defined($job_id_no)) {
	# {{{ Specific client name
	my $client_name_num = 1;
	&echo(0, "=> OID_BASE.jobsIDTable.jobsIDEntry.IndexJobIDs\n") if($CFG{'DEBUG'} > 1);
	foreach my $client_name (sort keys %CLIENTS) {
	    if($client_name_num == $CLIENT_NO) {
		my $job_name_num = 1;
		foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
		    if($job_name_num == $JOB_NO) {
			my $job_id_num = 1;
			foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
			    if($job_id_num == $job_id_no) {
				&echo(0, "$OID_BASE.7.1.1.$client_name_num.$job_name_num.$job_id_num = $job_id_num\n") if($CFG{'DEBUG'});
				
				&echo(1, "$OID_BASE.7.1.1.$client_name_num.$job_name_num.$job_id_num\n");
				&echo(1, "integer\n");
				&echo(1, "$job_id_num\n");
				
				$success = 1;
			    }

			    $job_id_num++;
			}
		    }
		
		    $job_name_num++;
		}
	    }
	    
	    $client_name_num++;
	}
# }}}
    } else {
	# {{{ ALL clients, all job status
	my $client_name_num = 1;
	&echo(0, "=> OID_BASE.jobsIDTable.jobsIDEntry.IndexJobIDs\n") if($CFG{'DEBUG'} > 1);
	foreach my $client_name (sort keys %CLIENTS) {
	    my $job_name_num = 1;
	    foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
		my $job_id_num = 1;
		foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
		    &echo(0, "$OID_BASE.7.1.1.$client_name_num.$job_name_num.$job_id_num = $job_id_num\n") if($CFG{'DEBUG'});
		    
		    &echo(1, "$OID_BASE.7.1.1.$client_name_num.$job_name_num.$job_id_num\n");
		    &echo(1, "integer\n");
		    &echo(1, "$job_id_num\n");
		    
		    $success = 1;
		    $job_id_num++;
		}
		
		$job_name_num++;
	    }
	    
	    $client_name_num++;
	}
# }}}
    }

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return $success;
}
# }}}

# {{{ OID_BASE.7.1.2.x.y.z	Output the job ID's
sub print_jobs_ids {
    my $job_name_no = shift;
    my $success = 0;

    if(defined($job_name_no)) {
	# {{{ Specific client name
	my $client_name_num = 1;
	&echo(0, "=> OID_BASE.jobsIDTable.jobsIDEntry.clientID.jobName.jobID\n") if($CFG{'DEBUG'} > 1);
	foreach my $client_name (sort keys %CLIENTS) {
	    if($client_name_num == $CLIENT_NO) {
		my $job_name_num = 1;
		&echo(0, "=> Client name: '$client_name'\n") if($CFG{'DEBUG'} > 3);
		foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
		    if($job_name_num == $JOB_NO) {
			my $job_id_num = 1;
			&echo(0, "=>   Job name: '$job_name'\n") if($CFG{'DEBUG'} > 3);
			foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
			    if($job_id_num == $job_name_no) {
				&echo(0, "=>     Job ID: '$job_id'\n") if($CFG{'DEBUG'} > 3);
				
				&echo(0, "$OID_BASE.7.1.2.$client_name_num.$job_name_num.$job_id_num = $job_id\n") if($CFG{'DEBUG'});
				
				&echo(1, "$OID_BASE.7.1.2.$client_name_num.$job_name_num.$job_id_num\n");
				&echo(1, "string\n");
				&echo(1, "$job_id\n");
				
				$success = 1;
			    }

			    $job_id_num++;
			}
		    }

		    $job_name_num++;
		}
	    }
	    
	    $client_name_num++;
	}
# }}}
    } else {
	# {{{ ALL clients, all job status
	my $client_name_num = 1;
	&echo(0, "=> OID_BASE.jobsIDTable.jobsIDEntry.clientID.jobName.jobID\n") if($CFG{'DEBUG'} > 1);
	foreach my $client_name (sort keys %CLIENTS) {
	    my $job_name_num = 1;
	    &echo(0, "=> Client name: '$client_name'\n") if($CFG{'DEBUG'} > 3);
	    foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
		my $job_id_num = 1;
		&echo(0, "=>   Job name: '$job_name'\n") if($CFG{'DEBUG'} > 3);
		foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
		    &echo(0, "=>     Job ID: '$job_id'\n") if($CFG{'DEBUG'} > 3);
		    
		    &echo(0, "$OID_BASE.7.1.2.$client_name_num.$job_name_num.$job_id_num = $job_id\n") if($CFG{'DEBUG'});
		    
		    &echo(1, "$OID_BASE.7.1.2.$client_name_num.$job_name_num\n");
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

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return $success;
}
# }}}


# {{{ OID_BASE.8.1.1.#		Output the job status counters index
sub print_jobs_status_counters_index {
    my $key_nr = shift;
    my $success = 0;
    my($i, $max);

    &echo(0, "=> OID_BASE.statsTable.statsEntry.statsTypeName\n") if($CFG{'DEBUG'} > 1);

    if(defined($key_nr)) {
	# {{{ One specific type name
	my $value = sprintf("%02d", $key_nr+1); # This is the index - offset one!
	if(!$keys_stats{$value}) {
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
	&echo(0, "$OID_BASE.8.1.1.$i = $i\n") if($CFG{'DEBUG'});

	&echo(1, "$OID_BASE.8.1.1.$i\n");
	&echo(1, "integer\n");
	&echo(1, "$i\n");

	$success = 1;
    }
# }}}

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return $success;
}
# }}}

# {{{ OID_BASE.8.1.2.#		Output the job status counters
sub print_jobs_status_counters {
    my $key_nr = shift;
    my $success = 0;
    my($i, $max);

    &echo(0, "=> OID_BASE.statsTable.statsEntry.statsTypeName\n") if($CFG{'DEBUG'} > 1);

    if(defined($key_nr)) {
	# {{{ One specific type name
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
	my $value = sprintf("%02d", $i+1);
	my $key_name = $keys_stats{$value};

	&echo(0, "$OID_BASE.8.1.2.$i = $key_name\n") if($CFG{'DEBUG'});

	&echo(1, "$OID_BASE.8.1.2.$i\n");
	&echo(1, "string\n");
	&echo(1, "$key_name\n");

	$success = 1;
    }
# }}}

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return $success;
}
# }}}


# {{{ OID_BASE.9.1.1.x.y.z.#	Output job status index
sub print_jobs_status_index {
    my $key_nr = shift;
    my $success = 0;

    &echo(0, "=> OID_BASE.statsTable.statsEntry.IndexStats\n") if($CFG{'DEBUG'} > 1);

    if(defined($key_nr)) {
	# {{{ One specific status index number
	my $client_name_num = 1; # Client number
	foreach my $client_name (sort keys %CLIENTS) {
	    if($client_name_num == $CLIENT_NO) {
		my $job_name_num = 1; # Job Name
		foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
		    if($job_name_num == $JOB_NO) {
			my $job_id_num = 1; # Job ID number
			foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
			    if($job_id_num == $key_nr) {
				&echo(0, "$OID_BASE.9.1.1.$client_name_num.$job_name_num.$job_id_num = $job_id_num\n") if($CFG{'DEBUG'});
				
				&echo(1, "$OID_BASE.9.1.1.$client_name_num.$job_name_num.$job_id_num\n");
				&echo(1, "integer\n");
				&echo(1, "$job_id_num\n");
				
				$success = 1;
			    }

			    $job_id_num++;
			}
		    }

		    $job_name_num++;
		}
	    }

	    $client_name_num++;
	}
# }}}
    } else {
	# {{{ ALL status indexes
	my $client_name_num = 1; # Client number
	foreach my $client_name (sort keys %CLIENTS) {
	    my $job_name_num = 1; # Job Name
	    foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
		my $job_id_num = 1; # Job ID number
		foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
		    &echo(0, "$OID_BASE.9.1.1.$client_name_num.$job_name_num.$job_id_num = $job_id_num\n") if($CFG{'DEBUG'});
		    
		    &echo(1, "$OID_BASE.9.1.1.$client_name_num.$job_name_num.$job_id_num\n");
		    &echo(1, "integer\n");
		    &echo(1, "$job_id_num\n");
		    
		    $success = 1;
		    $job_id_num++;
		}
		
		$job_name_num++;
	    }
	    
	    $client_name_num++;
	}
# }}}
    }

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return $success;
}
# }}}

# {{{ OID_BASE.9.1.X.x.y.z.#	Output job status
sub print_jobs_status {
    my $job_status_nr = shift;
    my $success = 0;

    if(defined($CLIENT_NO)) {
	# {{{ Status for a specific client, specific job ID and a specific type
	if(!$CLIENTS[$CLIENT_NO]) {
	    &echo(0, "=> No value in this object\n") if($CFG{'DEBUG'} > 1);
	    return 0;
	}

	foreach my $key_nr (sort keys %keys_stats) {
	    if($key_nr == $TYPE_STATUS) {
		my $key_name = $keys_stats{$key_nr};
		$key_nr =~ s/^0//;

		my $client_name_num = 1; # Client number
		foreach my $client_name (sort keys %CLIENTS) {
		    if($client_name_num == $CLIENT_NO) {

			my $job_name_num = 1; # Job Name
			foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
			    if($job_name_num == $JOB_NO) {
				my $job_id_num = 1; # Job ID number
				foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
				    if($job_id_num == $job_status_nr) {
					&echo(0, "=> OID_BASE.statsTable.statsEntry.$key_name.clientId.jobNr\n") if($CFG{'DEBUG'} > 1);

					&echo(0, "$OID_BASE.9.1.$key_nr.$client_name_num.$job_name_num.$job_id_num = ".
					      $STATUS{$client_name}{$job_name}{$job_id}{$key_name}."\n") if($CFG{'DEBUG'});
					
					&echo(1, "$OID_BASE.9.1.$key_nr.$client_name_num.$job_name_num.$job_id_num\n");
					if(($key_name eq 'start_date') || ($key_name eq 'end_date') || ($key_name eq 'type')) {
					    &echo(1, "string\n");
					} elsif($key_name eq 'bytes') {
					    &echo(1, "counter\n");
					} else {
					    &echo(1, "integer\n");
					}
					&echo(1, $STATUS{$client_name}{$job_name}{$job_id}{$key_name}."\n");
					
					return 1;
				    }
				    
				    $job_id_num++;
				}
			    }
			    
			    $job_name_num++;
			}
		    }

		    $ client_name_num++;
		}
	    }
	}
# }}}
    } else {
	# {{{ ALL clients, all job status
	foreach my $key_nr (sort keys %keys_stats) {
	    my $key_name = $keys_stats{$key_nr};
	    $key_nr =~ s/^0//;
	    &echo(0, "=> OID_BASE.statsTable.statsEntry.$key_name.clientId.jobNr\n") if($CFG{'DEBUG'} > 1);

	    my $client_name_num = 1; # Client number
	    foreach my $client_name (sort keys %CLIENTS) {
		my $job_name_num = 1; # Job Name
		foreach my $job_name (sort keys %{ $STATUS{$client_name} }) {
		    my $job_id_num = 1; # Job ID number
		    foreach my $job_id (sort keys %{ $STATUS{$client_name}{$job_name} }) {
			&echo(0, "$OID_BASE.9.1.$key_nr.$client_name_num.$job_name_num.$job_id_num = ".
			      $STATUS{$client_name}{$job_name}{$job_id}{$key_name}."\n") if($CFG{'DEBUG'});

			&echo(1, "$OID_BASE.9.1.$key_nr.$client_name_num.$job_name_num.$job_id_num\n");
			if(($key_name eq 'start_date') || ($key_name eq 'end_date') || ($key_name eq 'type')) {
			    &echo(1, "string\n");
			} elsif($key_name eq 'bytes') {
			    &echo(1, "counter\n");
			} else {
			    &echo(1, "integer\n");
			}
			&echo(1, $STATUS{$client_name}{$job_name}{$job_id}{$key_name}."\n");
			
			$success = 1;
			$job_id_num++;
		    }

		    $job_name_num++;
		}

		$client_name_num++;
	    }

	    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
	}
# }}}
    }

    return $success;
}
# }}}


# {{{ OID_BASE.10.1.1.x		Output pool index
sub print_pool_index {
    my $pool_no = shift; # Pool number
    my($i, $max);
    my $success = 0;
    &echo(0, "=> OID_BASE.poolsTable.poolsEntry.IndexPools\n") if($CFG{'DEBUG'} > 1);

    if(defined($pool_no)) {
	# {{{ Specific pool index
	if($pool_no > $POOLS) {
	    &echo(0, "=> No value in this object ($pool_no)\n") if($CFG{'DEBUG'});
	    return 0;
	}
    
	$i = $pool_no;
	$max = $pool_no;
# }}}
    } else {
	# {{{ The FULL pool index
	$i = 1;
	$max = $POOLS;
# }}}
    }

    # {{{ Output index
    for(; $i <= $max; $i++) {
	&echo(0, "$OID_BASE.10.1.1.$i = $i\n") if($CFG{'DEBUG'});

	&echo(1, "$OID_BASE.10.1.1.$i\n");
	&echo(1, "integer\n");
	&echo(1, "$i\n");

	$success = 1;
    }
# }}}

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return $success;
}
# }}}

# {{{ OID_BASE.10.1.X.x		Output pool information
sub print_pool_names {
    my $pool_no = shift; # Pool number
    my $success = 0;
    &echo(0, "=> OID_BASE.poolTable.poolEntry.key.jobid\n") if($CFG{'DEBUG'} > 1);

    if(defined($pool_no)) {
	# {{{ Specific pool index
	foreach my $key_nr (sort keys %keys_pool) {
	    my $value = sprintf("%02d", $TYPE_STATUS);
	    if($key_nr == $value) {
		my $key_name = $keys_pool{$key_nr};
		$key_nr =~ s/^0//;
		
		my $pool_nr = 1;
		foreach my $pool_id (sort keys %POOLS) {
		    if($pool_nr == $pool_no) {
			&echo(0, "=> OID_BASE.poolTable.poolEntry->$pool_id.$key_name\n") if($CFG{'DEBUG'} > 1);

			&echo(0, "$OID_BASE.10.1.$key_nr.$pool_nr = ".$POOLS{$pool_id}{$key_name}."\n") if($CFG{'DEBUG'});
			
			&echo(1, "$OID_BASE.10.1.$key_nr.$pool_nr\n");

			# OID_BASE.10.1.{3,16,17} is strings, all others integers!
			if(($key_name eq 'id') ||
			   ($key_name eq 'type') ||
			   ($key_name eq 'label_format'))
			{
			    &echo(1, "string\n");
			} elsif(($key_name eq 'vol_retention') ||
				($key_name eq 'vol_use_duration') ||
				($key_name eq 'max_bytes'))
			{
			    &echo(1, "counter\n");
			} else {
			    &echo(1, "integer\n");
			}
			&echo(1, $POOLS{$pool_id}{$key_name}."\n");
			
			$success = 1;
		    }

		    $pool_nr++;
		}
	    }
	}
# }}}
    } else {
	# {{{ The FULL pool index
	foreach my $key_nr (sort keys %keys_pool) {
	    my $key_name = $keys_pool{$key_nr};
	    $key_nr =~ s/^0//;
	    
	    my $pool_nr = 1;
	    foreach my $pool_id (sort keys %POOLS) {
		&echo(0, "$OID_BASE.10.1.$key_nr.$pool_nr = ".$POOLS{$pool_id}{$key_name}."\n") if($CFG{'DEBUG'});
		
		&echo(1, "$OID_BASE.10.1.$key_nr.$pool_nr\n");
		if(($key_name eq 'id') ||
		   ($key_name eq 'type') ||
		   ($key_name eq 'label_format'))
		{
		    &echo(1, "string\n");
		} elsif(($key_name eq 'vol_retention') ||
			($key_name eq 'vol_use_duration') ||
			($key_name eq 'max_bytes'))
		{
		    &echo(1, "counter\n");
		} else {
		    &echo(1, "integer\n");
		}
		&echo(1, $POOLS{$pool_id}{$key_name}."\n");
		
		$success = 1;
	    }
	    
	    $pool_nr++;
	}
# }}}
    }

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return $success;
}
# }}}


# {{{ OID_BASE.11.1.1.x		Output media index
sub print_media_index {
    my $media_no = shift; # Media number
    my($i, $max);
    my $success = 0;
    &echo(0, "=> OID_BASE.mediaTable.mediaEntry.IndexMedia\n") if($CFG{'DEBUG'} > 1);

    if(defined($media_no)) {
	# {{{ Specific media index
	if($media_no > $MEDIAS) {
	    &echo(0, "=> No value in this object ($media_no)\n") if($CFG{'DEBUG'});
	    return 0;
	}
    
	$i = $media_no;
	$max = $media_no;
# }}}
    } else {
	# {{{ The FULL media index
	$i = 1;
	$max = $MEDIAS;
# }}}
    }

    # {{{ Output index
    for(; $i <= $max; $i++) {
	&echo(0, "$OID_BASE.11.1.1.$i = $i\n") if($CFG{'DEBUG'});

	&echo(1, "$OID_BASE.11.1.1.$i\n");
	&echo(1, "integer\n");
	&echo(1, "$i\n");

	$success = 1;
    }
# }}}

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return $success;
}
# }}}

# {{{ OID_BASE.11.1.X.x		Output media index
sub print_media_names {
    my $media_no = shift; # Media number
    my $success = 0;

    if(defined($media_no)) {
	# {{{ Specific media index
	foreach my $key_nr (sort keys %keys_media) {
	    my $value = sprintf("%02d", $TYPE_STATUS);
	    if($key_nr == $value) {
		my $key_name = $keys_media{$key_nr};
		$key_nr =~ s/^0//;
		&echo(0, "=> OID_BASE.mediaTable.mediaEntry.$key_name\n") if($CFG{'DEBUG'} > 1);

		my $media_nr = 1;
		foreach my $media_id (sort keys %MEDIAS) {
		    if($media_nr == $media_no) {
			&echo(0, "$OID_BASE.11.1.$key_nr.$media_nr = ".$MEDIAS{$media_id}{$key_name}."\n") if($CFG{'DEBUG'});
			
			&echo(1, "$OID_BASE.11.1.$key_nr.$media_nr\n");
			if(($key_name eq 'name') ||
			   ($key_name eq 'type') ||
			   ($key_name eq 'first_written') ||
			   ($key_name eq 'last_written') ||
			   ($key_name eq 'label_date'))
			{
			    &echo(1, "string\n");
			} elsif(($key_name eq 'bytes') ||
				($key_name eq 'capacity') ||
				($key_name eq 'retention') ||
				($key_name eq 'use_duration') ||
				($key_name eq 'max_bytes') ||
				($key_name eq 'read_time') ||
				($key_name eq 'write_time'))
			{
			    &echo(1, "counter\n");
			} else {
			    &echo(1, "integer\n");
			}
			&echo(1, $MEDIAS{$media_id}{$key_name}."\n");
			
			$success = 1;
		    }

		    $media_nr++;
		}
	    }
	}
# }}}
    } else {
	# {{{ The FULL media index
	foreach my $key_nr (sort keys %keys_media) {
	    my $key_name = $keys_media{$key_nr};
	    $key_nr =~ s/^0//;

	    &echo(0, "=> OID_BASE.mediaTable.mediaEntry.$key_name\n") if($CFG{'DEBUG'} > 1);
	    
	    my $media_nr = 1;
	    foreach my $media_id (sort keys %MEDIAS) {
		&echo(0, "$OID_BASE.11.1.$key_nr.$media_nr = ".$MEDIAS{$media_id}{$key_name}."\n") if($CFG{'DEBUG'});
		
		&echo(1, "$OID_BASE.11.1.$key_nr.$media_nr\n");
		if(($key_name eq 'name') ||
		   ($key_name eq 'type') ||
		   ($key_name eq 'first_written') ||
		   ($key_name eq 'last_written') ||
		   ($key_name eq 'label_date'))
		{
		    &echo(1, "string\n");
		} elsif(($key_name eq 'bytes') ||
			($key_name eq 'capacity') ||
			($key_name eq 'retention') ||
			($key_name eq 'use_duration') ||
			($key_name eq 'max_bytes') ||
			($key_name eq 'read_time') ||
			($key_name eq 'write_time'))
		{
		    &echo(1, "counter\n");
		} else {
		    &echo(1, "integer\n");
		}
		&echo(1, $MEDIAS{$media_id}{$key_name}."\n");
		
		$success = 1;
		$media_nr++;
	    }

	    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
	}
# }}}
    }

    return $success;
}
# }}}

# ====================================================
# =====       W R I T E  F U N C T I O N S       =====

# {{{ OID_BASE.5.1.4
sub write_client_autoprune {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_client_autoprune($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'integer');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Client SET AutoPrune=$arg_val WHERE ClientId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
}
# }}}

# {{{ OID_BASE.5.1.5
sub write_client_retentionfile {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_client_retentionfile($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'integer');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Client SET FileRetention=$arg_val WHERE ClientId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
}
# }}}

# {{{ OID_BASE.5.1.6
sub write_client_retentionjob {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_client_retentionjob($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'integer');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Client SET JobRetention=$arg_val WHERE ClientId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
}
# }}}

# {{{ OID_BASE.10.1.5
sub write_pools_useonce {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_pools_useonce($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'integer');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Pool SET UseOnce=$arg_val WHERE PoolId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
}
# }}}

# {{{ OID_BASE.10.1.6
sub write_pools_usecatalog {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_pools_usecatalog($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'integer');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Pool SET UseCatalog=$arg_val WHERE PoolId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
}
# }}}

# {{{ OID_BASE.10.1.7
sub write_pools_acceptanyvolume {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_pools_acceptanyvolume($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'integer');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Pool SET AcceptAnyVolume=$arg_val WHERE PoolId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
}
# }}}

# {{{ OID_BASE.10.1.8
sub write_pools_retention {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_pools_retention($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'integer');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Pool SET VolRetention=$arg_val WHERE PoolId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
}
# }}}

# {{{ OID_BASE.10.1.9
sub write_pools_duration {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_pools_duration($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'integer');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Pool SET VolUseDuration=$arg_val WHERE PoolId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
}
# }}}

# {{{ OID_BASE.10.1.10
sub write_pools_maxjobs {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_pools_maxjobs($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'integer');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Pool SET MaxVolJobs=$arg_val WHERE PoolId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
}
# }}}

# {{{ OID_BASE.10.1.11
sub write_pools_maxfiles {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_pools_maxfiles($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'integer');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Pool SET MaxVolFiles=$arg_val WHERE PoolId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
}
# }}}

# {{{ OID_BASE.10.1.12
sub write_pools_maxbytes {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_pools_maxbytes($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'integer');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Pool SET MaxVolBytes=$arg_val WHERE PoolId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
}
# }}}

# {{{ OID_BASE.10.1.13
sub write_pools_autoprune {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_pools_autoprune($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'integer');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Pool SET AutoPrune=$arg_val WHERE PoolId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
}
# }}}

# {{{ OID_BASE.10.1.14
sub write_pools_recycle {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_pools_recycle($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'integer');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Pool SET Recycle=$arg_val WHERE PoolId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
}
# }}}

# {{{ OID_BASE.10.1.15
sub write_pools_type {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_pools_type($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'string');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Pool SET PoolType=$arg_val WHERE PoolId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
}
# }}}

# {{{ OID_BASE.10.1.16
sub write_pools_labelformat {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_pools_labelformat($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'string');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Pool SET LabelFormat=$arg_val WHERE PoolId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
}
# }}}

# {{{ OID_BASE.10.1.17
sub write_pools_enabled {
    my $arg_sub  = shift;
    my $arg_type = shift;
    my $arg_val  = shift;

    &echo(0, "=> write_pools_enabled($arg_sub, $arg_type, $arg_val)\n") if($CFG{'DEBUG'} > 3);

    return 2 if($arg_type ne 'integer');

    # {{{ Setup and execute the SQL query
    my ($QUERY, $sth) = ("UPDATE Pool SET Enabled=$arg_val WHERE PoolId=$arg_sub", 0);

    # Prepare query
    if(!($sth = $dbh->prepare($QUERY))) {
	&echo(0, "=> ERROR: Could not prepare SQL query: $dbh->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query prepared: '$QUERY'\n") if($CFG{'DEBUG'} > 3);

    # Execute query
    if(!$sth->execute) {
	&echo(0, "Could not execute query: $sth->errstr\n");
	return(2);
    }
    &echo(0, "=> SQL query executed\n") if($CFG{'DEBUG'} > 3);
# }}}

    return(0);
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

# {{{ Call function with option - print
sub call_print {
    my $func_nr  = shift;
    my $func_arg = shift;
    my $function;

    # First level of the oid is in my variables
    # prefixed with a '0' to allow correct sorting
    # in the code. If it doesn't exists, add it...
    if(($func_nr =~ /$OID_BASE\.[1-9]/) && ($func_nr !~ /$OID_BASE\.[1-9][0-9]/)) {
	$func_nr  =~ s/$OID_BASE\./$OID_BASE\.0/;
    }

    # Make sure that the argument variable is initialized
    $func_arg =  '' if(!$func_arg);

    &echo(0, "=> call_print($func_nr, $func_arg)\n") if($CFG{'DEBUG'} > 3);
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

    if(defined($function)) {
	&echo(0, "=> Calling function '$function($func_arg)'\n") if($CFG{'DEBUG'} > 2);
	
	$function = \&{$function}; # Because of 'use strict' above...
	&$function($func_arg);
    } else {
	return 0;
    }
}
# }}}

# {{{ Call function with option - write
sub call_write {
    my $func_base = shift;
    my $func_sub  = shift;
    my $func_type = shift;
    my $func_arg  = shift;
    my $function;

    &echo(0, "=> call_write($func_base, $func_sub, $func_type, $func_arg)\n") if($CFG{'DEBUG'} > 3);
    my $func = $writables{$OID_BASE.".".$func_base};
    return 1 if(!defined($func));

    $function = "write_".$func;
    &echo(0, "=> Calling function '$function($func_sub, $func_type, $func_arg)'\n") if($CFG{'DEBUG'} > 2);

    $function = \&{$function}; # Because of 'use strict' above...
    return(&$function($func_sub, $func_type, $func_arg));
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

    # Get job information
    ($JOBS, %JOBS) = &get_info_jobs();

    # Put toghether the CLIENTS array
    my $i = 1;
    foreach my $client_name (keys %CLIENTS) {
	$CLIENTS[$i] = $i.";".$client_name;
	$i++;
    }

    # Schedule an alarm once every hour to re-read information.
    alarm(60*60);
}
# }}}

# {{{ Return 'no such value'
sub no_value {
    &echo(0, "=> No value in this object - exiting!\n") if($CFG{'DEBUG'} > 1);
    
    &echo(1, "NONE\n");
    &echo(0, "\n") if($CFG{'DEBUG'} > 1);
}
# }}}

# {{{ Get next value from a set of input
sub get_next_oid {
    my @tmp = @_;

    &output_extra_debugging(@tmp) if($CFG{'DEBUG'} > 3);

    # next1 => Base OID to use in call
    # next2 => next1.next2 => Full OID to retreive
    # next3 => Client number (OID_BASE.4) or Job ID (OID_BASE.9)
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
	# {{{ ------------------------------------- OID_BASE.5       
	$TYPE_STATUS = $tmp[2];
	$CLIENT_NO   = $tmp[3];
# }}} # OID_BASE.5
    } elsif(($tmp[0] >= 6) && ($tmp[0] <= 9)) {
	# {{{ ------------------------------------- OID_BASE.[6-9]   
	# StatsIndex, StatsTypesName and JobID list
	$TYPE_STATUS = $tmp[2];
	$CLIENT_NO   = $tmp[3];
	$JOB_NO      = $tmp[4];
# }}} # OID_BASE.[5-8]
    } elsif(($tmp[0] >= 10) && ($tmp[0] <= 11)) {
	# {{{ ------------------------------------- OID_BASE.[10-11] 
	$TYPE_STATUS = $tmp[2];
	$CLIENT_NO   = $tmp[3];
# }}} # OID_BASE.[10-11]
    } else {
	$CLIENT_NO   = $tmp[3];
	$TYPE_STATUS = $tmp[4];
    }

    if($CFG{'DEBUG'} > 2) {
	my $string;
	$string  = "TYPE_STATUS=$TYPE_STATUS" if(defined($TYPE_STATUS));
	$string .= ", " if($string);
	$string .= "CLIENT_NO=$CLIENT_NO" if(defined($CLIENT_NO));
	$string .= ", " if($string);
	$string .= "JOB_NO=$JOB_NO" if(defined($JOB_NO));
	
	&echo(0, "=> get_next_oid(): $string\n");
    }

    return($next1, $next2, $next3);
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
foreach (keys %keys_client) { $TYPES_CLIENT++; }
foreach (keys %keys_jobs)   { $TYPES_JOBS++;   }
foreach (keys %keys_stats)  { $TYPES_STATS++;  }
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
    # {{{ Extend the '%functions' array
    my($i, $j);

    # Add an entry for each client to the '%functions' array
    # Call 'print_clients_name()' for ALL clients - dynamic amount,
    # so we can't hardcode them in the initialisation at the top
    ($i, $j) = (2, 3);
    for(; $i <= $TYPES_CLIENT; $i++, $j++) {
	$functions{$OID_BASE.".05.1.$j"} = "clients_name";
    }

    # Add an entry for each job name to the '%functions' array
    # Call 'print_jobs_names()' for ALL clients - dynamic amount,
    # so we can't hardcode them in the initialisation at the top
    $j = 3;
    foreach my $client_name (sort keys %CLIENTS) {
	foreach my $job (sort keys %{ $CLIENTS{$client_name} }) {
	    $functions{$OID_BASE.".06.1.$j"} = "jobs_names";
	    $j++
	}
    }

    # Add the '%keys_stats' array to the '%functions' array
    # First one is already there, so start with the second with value '5'...
    # We do that here instead of at the very top so that output of ALL
    # works without calling print_jobs_status() FIVE times...
    #
    # OID_BASE.09.1.1: types_index	Already exists in %functions
    # OID_BASE.09.1.2: jobs_status	Already exists in %functions	start_date
    # OID_BASE.09.1.3: jobs_status	Add this to %functions		end_date
    # OID_BASE.09.1.4: jobs_status	Add this to %functions		duration
    # OID_BASE.09.1.5: jobs_status	Add this to %functions		files
    # OID_BASE.09.1.6: jobs_status	Add this to %functions		bytes
    ($i, $j) = (2, 3);
    for(; $i <= $TYPES_STATS; $i++, $j++) {
	$functions{$OID_BASE.".09.1.$j"} = "jobs_status";
    }

    # Add the '%keys_pool' array to the '%functions' array
    # First one is already there, so start with the second with value '4'...
    ($i, $j) = (2, 3);
    for(; $i <= $TYPES_POOL; $i++, $j++) {
	$functions{$OID_BASE.".10.1.$j"} = "pool_names";
    }

    # Add the '%keys_media' array to the '%functions' array
    # First one is already there, so start with the second with value '4'...
    ($i, $j) = (2, 3);
    for(; $i <= $TYPES_MEDIA; $i++, $j++) {
	$functions{$OID_BASE.".11.1.$j"} = "media_names";
    }
# }}}

    # {{{ Go through the commands sent on STDIN
    while(<>) {
	if (m!^PING!){
	    print "PONG\n";
	    next;
	}

	# Re-get the DEBUG config option (so that we don't have to restart process).
	get_config('DEBUG');

	# {{{ Get all run arguments - next/specfic OID
	my $arg = $_; chomp($arg);

	# Get next line from STDIN -> OID number.
	# $arg == 'getnext' => Get next OID
	# $arg == 'get'     => Get specified OID
	# $arg == 'set'     => Set value for OID
	$oid = <>; chomp($oid);
	$oid =~ s/$OID_BASE//; # Remove the OID base
	$oid =~ s/OID_BASE//;  # Remove the OID base (if we're debugging)
	$oid =~ s/^\.//;       # Remove the first dot if it exists - it's in the way!

	&echo(0, "=> ARG='$arg  $OID_BASE.$oid'\n") if($CFG{'DEBUG'} >= 2);
	
	my @tmp = split('\.', $oid);
	&output_extra_debugging(@tmp) if($CFG{'DEBUG'} > 2);
# }}}
	
	if($arg eq 'getnext') {
	    # {{{ Get next OID
	    if(!defined($tmp[0])) {
		# {{{ ------------------------------------- OID_BASE         
		&call_print($OID_BASE.".1");
# }}} # OID_BASE

	    } elsif(($tmp[0] >= 1) && ($tmp[0] <= 4)) {
		# {{{ ------------------------------------- OID_BASE.[1-4]   
		if(!defined($tmp[1])) {
		    &call_print($OID_BASE.".".$tmp[0]);
		} else {
		    $tmp[0]++;
		    
		    if($tmp[0] >= 5) {
			for(my $i=1; $i <= 3; $i++) { $tmp[$i] = 1; }

			# How to call call_print()
			my($next1, $next2, $next3) = get_next_oid(@tmp);

			&echo(0, ">> Get next OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} >= 2);
			&call_print($next1, $next3);
		    } else {
			&call_print($OID_BASE.".".$tmp[0]);
		    }
		}
# }}} # OID_BASE.[1-4]

	    } elsif( $tmp[0] == 5) {
		# {{{ ------------------------------------- OID_BASE.5       
		# {{{ Figure out the NEXT value from the input
		if(!defined($tmp[1]) || !defined($tmp[2])) {
		    # Called only as 'OID_BASE.5'
		    for(my $i=1; $i <= 3; $i++) { $tmp[$i] = 1; }
		} elsif(!defined($tmp[3])) {
		    # Called only as 'OID_BASE.5.1.x'
		    $tmp[3] = 1;
		} else {
		    if($tmp[2] >= $TYPES_CLIENT+2) {
			# We've reached the ned of the OID_BASE.5.1.x -> OID_BASE.6.1.1.1.1
			$tmp[0]++;
			for(my $i=1; $i <= 3; $i++) { $tmp[$i] = 1; }
		    } elsif($tmp[3] >= $CLIENTS) {
			# We've reached the end of the OID_BASE.5.1.x.y -> OID_BASE.5.1.x+1.1
			$tmp[2]++;
			$tmp[3] = 1;
		    } else {
			# Get OID_BASE.5.1.x.y+1
			$tmp[3]++;
		    }
		}

		# How to call call_print()
		my($next1, $next2, $next3) = get_next_oid(@tmp);
# }}} # Figure out next value

		&echo(0, ">> Get next OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} >= 2);
		if(!&call_print($next1, $next3)) {
		    # OID_BASE.5.1.2.4 => OID_BASE.5.1.2.5 => OID_BASE.5.1.3.1
		    # {{{ Figure out the NEXT value from the input
		    $tmp[0]++;
		    for(my $i=1; $i <= 3; $i++) { $tmp[$i] = 1; }

		    # How to call call_print()
		    my($next1, $next2, $next3) = get_next_oid(@tmp);
# }}} # Figure out next value

		    &echo(0, ">> No OID at that level (-1) - get next branch OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} >= 2);
		    &call_print($next1, $next3);
		}
# }}} # OID_BASE.5

	    } elsif(($tmp[0] >= 6) &&  ($tmp[0] <= 9)) {
		# {{{ ------------------------------------- OID_BASE.[6-9]   
		# {{{ Figure out the NEXT value from the input
		if($tmp[0] == 6) {
		    # {{{ OID_BASE.6
		    if(!defined($tmp[1]) || !defined($tmp[2])) {
			# Called with 'OID_BASE.6'
			for(my $i=1; $i <= 2; $i++) { $tmp[$i] = 1; }
		    } elsif(!defined($tmp[3]) || !defined($tmp[4])) {
			# Called with 'OID_BASE.6.1.x'
			for(my $i=3; $i <= 4; $i++) { $tmp[$i] = 1; }
		    } else {
			$tmp[4]++;
		    }
# }}} # OID_BASE.6

		} elsif($tmp[0] == 7) {
		    # {{{ OID_BASE.7
		    if(!defined($tmp[1]) || !defined($tmp[2])) {
			# Called with 'OID_BASE.7'
			for(my $i=1; $i <= 5; $i++) { $tmp[$i] = 1; }
		    } elsif(!defined($tmp[3]) || !defined($tmp[4]) || !defined($tmp[5])) {
			# Called with 'OID_BASE.7.1.x'
			for(my $i=3; $i <= 4; $i++) { $tmp[$i] = 1; }
		    } else {
			$tmp[5]++;
		    }
# }}} # OID_BASE.7

		} elsif($tmp[0] == 8) {
		    # {{{ OID_BASE.8
		    if(!defined($tmp[1])) {
			for(my $i=1; $i <= 3; $i++) { $tmp[$i] = 1; }
		    } elsif(!defined($tmp[2])) {
			for(my $i=2; $i <= 3; $i++) { $tmp[$i] = 1; }
		    } elsif(!defined($tmp[3])) {
			$tmp[3] = 1;
		    } elsif($tmp[3] >= $TYPES_STATS) {
			# No more status counters
			if($tmp[2] == 1) {
			    # OID_BASE.8.1.1.x -> OID_BASE.8.1.2.1
			    $tmp[2]++;
			    $tmp[3] = 1;
			} else {
			    # OID_BASE.8.1.2.x -> OID_BASE.9.1.1.1.1.1
			    $tmp[0]++;
			    for(my $i=1; $i <= 5; $i++) { $tmp[$i] = 1; }
			}
		    } else {
			$tmp[3]++;
		    }
# }}} # OID_BASE.8

		} elsif($tmp[0] == 9) {
		    # {{{ OID_BASE.9
		    if(!defined($tmp[1]) || !defined($tmp[2])) {
			for(my $i=1; $i <= 3; $i++) { $tmp[$i] = 1; }

		    } elsif($tmp[2] == 1) {
			if(!defined($tmp[3])) {
			    # Called with 'OID_BASE.9.1.1' - index
			    for(my $i=3; $i <= 4; $i++) { $tmp[$i] = 1; }
			} elsif(!defined($tmp[4])) {
			    # Called with 'OID_BASE.9.1.1.x' - index
			    $tmp[4] = 1;
			} else {
			    $tmp[5]++;
			}

		    } elsif($tmp[2] > $TYPES_STATS+2) { # Offset two because of index etc.
			# End of the line for the OID_BASE.9.1.x -> OID_BASE.10.1.1.1
			$tmp[0]++;
			for(my $i=1; $i <= 3; $i++) { $tmp[$i] = 1; }

		    } elsif($tmp[2] >= 2) {
			if(!defined($tmp[3])) {
			    # Called with 'OID_BASE.9.1.[2-11]'
			    for(my $i=3; $i <= 5; $i++) { $tmp[$i] = 1; }
			} elsif(!defined($tmp[4])) {
			    # Called with 'OID_BASE.9.1.[2-11].x'
			    for(my $i=4; $i <= 5; $i++) { $tmp[$i] = 1; }
			} elsif(!defined($tmp[5])) {
			    # Called with 'OID_BASE.9.1.[2-11].x.y'
			    $tmp[5] = 1;
			} else {
			    $tmp[5]++;
			}
		    }
# }}} # OID_BASE.8
		}

		# How to call call_print()
		my($next1, $next2, $next3) = get_next_oid(@tmp);
# }}} # Figure out next value

		# {{{ Call functions, recursively (1)
		&echo(0, ">> Get next OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} >= 2);
		if(!&call_print($next1, $next3)) {
		    # Reached the end of OID_BASE.6.1.1.1.1 => OID_BASE.6.1.1.2.1
		    # {{{ Figure out the NEXT value from the input
		    if($tmp[0] == 6) {
			$tmp[3]++;
			$tmp[4] = 1;

		    } elsif($tmp[0] == 7) {
			$tmp[4]++;
			$tmp[5] = 1;

		    } elsif($tmp[0] == 9) {
			$tmp[4]++;
			$tmp[5] = 1;
		    }

		    # How to call call_print()
		    my($next1, $next2, $next3) = get_next_oid(@tmp);
# }}} # Figure out next value

		    # {{{ Call functions, recursively (-1)
		    &echo(0, ">> No OID at that level (-1) - get next branch OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} >= 2);
		    if(!&call_print($next1, $next3)) {
			# Reached the end of OID_BASE.6.1.1.x => OID_BASE.6.1.2.1.1
			# {{{ Figure out the NEXT value from the input
			if($tmp[0] == 6) {
			    $tmp[2]++;
			    for(my $i=3; $i <= 4; $i++) { $tmp[$i] = 1; }
			    
			    if($tmp[2] >= 6) {
				# No such branch OID_BASE.7.1.6 => OID_BASE.8.1.1.1.1.1
				$tmp[0]++;
				for(my $i=1; $i <= 5; $i++) { $tmp[$i] = 1; }
			    }

			} elsif(($tmp[0] == 7) || ($tmp[0] == 9)) {
			    $tmp[3]++;
			    for(my $i=4; $i <= 5; $i++) { $tmp[$i] = 1; }
			}
			
			# How to call call_print()
			my($next1, $next2, $next3) = get_next_oid(@tmp);
# }}} # Next value

			# {{{ Call functions, recursively (-2)
			&echo(0, ">> No OID at that level (-2) - get next branch OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} >= 2);
			if(!&call_print($next1, $next3)) {
			    # Reached the end of the OID_BASE.6.1.2 => OID_BASE.7.1.1.1.1.1
			    # {{{ Figure out the NEXT value from the input
			    if($tmp[0] == 6) {
				$tmp[0]++;
				for(my $i=1; $i <= 5; $i++) { $tmp[$i] = 1; }

			    } elsif(($tmp[0] == 7) || ($tmp[0] == 9)) {
				if(($tmp[0] == 7) && ($tmp[3] >= $CLIENTS)) {
				    # End of the line for OID_BASE.7.1.x => OID_BASE.8.1.1.1
				    $tmp[2]++;
				    for(my $i=3; $i <= 5; $i++) { $tmp[$i] = 1; }
				} else {
				    $tmp[2]++;
				    for(my $i=3; $i <= 5; $i++) { $tmp[$i] = 1; }
				    
				    if(($tmp[0] == 7) && ($tmp[2] >= 3)) {
					# No such branch OID_BASE.7.1.3 => OID_BASE.8.1.1.1
					$tmp[0]++;
					for(my $i=3; $i <= 5; $i++) { $tmp[$i] = 1; }
				    }
				}
			    }

			    # How to call call_print()
			    my($next1, $next2, $next3) = get_next_oid(@tmp);
# }}} # Next value

			    # {{{ Call functions, recursively (-3)
			    &echo(0, ">> No OID at that level (-3) - get next branch OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} >= 2);
			    if(!&call_print($next1, $next3)) {
				# Reached the end of the OID_BASE.7.1.2 => OID_BASE.8.1.1.1
				# {{{ Figure out the NEXT value from the input
				$tmp[0]++;
				$tmp[1] = 1;
				$tmp[2] = 1;
				$tmp[3] = 1;

				if($tmp[0] == 9) {
				    undef($tmp[4]); undef($tmp[5]);
				}

				# How to call call_print()
				my($next1, $next2, $next3) = get_next_oid(@tmp);
# }}} # Next value
				
				&echo(0, ">> No OID at that level (-4) - get next branch OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} >= 2);
				&call_print($next1, $next3);
			    }
# }}} # Call functions -> -3
			}
# }}} # Call functions -> -2
		    }
# }}} # Call functions -> -1
		}
# }}} # Call functions ->  1
# }}} OID_BASE.[6-8]

	    } elsif(($tmp[0] >= 10) && ($tmp[0] <= 11)) {
		# {{{ ------------------------------------- OID_BASE.[10-11] 
		# {{{ Figure out the NEXT value from the input
		if(!defined($tmp[1])) {
		    for(my $i=1; $i <= 3; $i++) { $tmp[$i] = 1; }
		} elsif(!defined($tmp[2])) {
		    for(my $i=2; $i <= 3; $i++) { $tmp[$i] = 1; }
		} elsif(!defined($tmp[3])) {
		    $tmp[3] = 1;
		} else {
		    $tmp[3]++;
		}
		
		# How to call call_print()
		my($next1, $next2, $next3) = get_next_oid(@tmp);
# }}} Figure out next value
		
		# {{{ Call functions, recursively (1)
		&echo(0, ">> Get next OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} >= 2);
		if(!&call_print($next1, $next3)) {
		    # {{{ Figure out the NEXT value from the input
		    if(($tmp[0] == 10) && ($tmp[3] >= $POOLS)) {
			# No more clients -> Next key, first client
			$tmp[2]++;
			$tmp[3] = 1;

		    } elsif(($tmp[0] == 11) && ($tmp[2] > $TYPES_MEDIA)) {
			&no_value();

		    } else {
			$tmp[2]++;
			$tmp[3] = 1;
		    }
		    
		    # How to call call_print()
		    my($next1, $next2, $next3) = get_next_oid(@tmp);
# }}} # Get next value

		    # {{{ Call functions, recursivly (-1)
		    &echo(0, ">> No OID at that level (-1) - get next branch OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} >= 2);
		    if(!&call_print($next1, $next3)) {
			# {{{ Figure out the NEXT value from the input
			if($tmp[0] == 10) {
			    if($tmp[2] >= $TYPES_POOL) {
				# No more values in OID_BASE.10.1.x -> OID_BASE.11.1.1.1
				$tmp[0]++;
				for(my $i=1; $i <= 3; $i++) { $tmp[$i] = 1; }
			    }
			}
		    
			# How to call call_print()
			my($next1, $next2, $next3) = get_next_oid(@tmp);
# }}} # Get next value

			# {{{ Call functions, recursivly (-2)
			&echo(0, ">> No OID at that level (-2) - get next branch OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} >= 2);
			&call_print($next1, $next3);
# }}} # Call functions (-2)
		    }
# }}} # Call functions (-1)
		}
# }}} # Call functions (1)
# }}} # OID_BASE.[9-10]

	    } else {
		# {{{ ------------------------------------- Unknown OID      
		&echo(0, "Error: No such OID '$OID_BASE' . '$oid'.\n") if($CFG{'DEBUG'});
		&echo(0, "\n") if($CFG{'DEBUG'} > 1);
		next;
# }}} # No such OID
	    }
# }}}
	} elsif($arg eq 'get') {
	    # {{{ Get _this_ OID
	    my($next1, $next2, $next3);
	    if(($tmp[0] >= 1) && ($tmp[0] <= 4)) {
		$next1 = "$OID_BASE.".$tmp[0];
		$next2 = '';
		$next3 = $tmp[1];
	    } else {
		# How to call call_print()
		($next1, $next2, $next3) = get_next_oid(@tmp);
	    }

	    &echo(0, "=> Get this OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} > 2);
	    if(!&call_print($next1, $next3)) {
		&no_value();
		next;
	    }
# }}} # Get _this_ OID
	} elsif($arg eq 'set') {
	    # {{{ Set a value
	    my $input  = <>; chomp($input);
	    my ($type, $value) = split(' ', $input);
	    &echo(0, "=> Type: '$type', Value: '$value'\n") if($CFG{'DEBUG'} > 3);

	    my $code = &call_write($tmp[0].".1.".$tmp[2], $tmp[3], $type, $value);
	    if($code == 0) {
		&echo(0, "=> Successfully modified object\n") if($CFG{'DEBUG'} > 2);
		&echo(1, "\n");
	    } elsif($code == 1) {
		&echo(0, "=> ERROR: Object not writable\n");
		&echo(1, "not-writable\n");
	    } elsif($code == 2) {
		&echo(0, "=> ERROR: Input of wrong type (='$type')\n");
		&echo(1, "wrong-type\n");
	    } else {
		&echo(0, "=> ERROR: Generic failure\n");
	    }

	    next;
# }}} # Set a value
	}

	&echo(0, "\n") if($CFG{'DEBUG'} > 1);
    }
# }}}
}
