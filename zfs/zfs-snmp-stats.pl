#!/usr/bin/perl -w

# {{{ Config file description and location.
# Require the file "/etc/bind/.bindsnmp" with the following
# defines (example values shown here!):
#
# If the location of the config file isn't good enough for you,
# feel free to change that here.
my $CFG_FILE = "/etc/zfs/.zfssnmp";
#
#   Optional arguments
#	DEBUG=4
#	DEBUG_FILE=/tmp/zfs-snmp.log
#
#   Required options
#	ZPOOL=/usr/sbin/zpool
#	ZFS=/usr/sbin/zfs
#	KSTATDIR=/proc/spl/kstat/zfs
#	RELOAD=10
#
# Comments must start at the beginning of the line, and continue to the
# end of the line. The comment character is any other character than
# a-z and A-Z.
#
# }}}

# {{{ Include libraries and setup global variables
# Forces a buffer flush after every print
$|=1;

use strict; 
use BayourCOM_SNMP;

$ENV{PATH}   = "/bin:/usr/bin:/usr/sbin";

# When debugging, it's easier to type this than the full OID
# This is changed (way) below IF/WHEN we're running through SNMPd!
my $OID_BASE = "OID_BASE";

# {{{ The 'flow' of the OID/MIB tree.
my %functions  = ($OID_BASE.".01"	=> "amount_pools",
		  $OID_BASE.".02"	=> "amount_datasets",
		  $OID_BASE.".03"	=> "amount_volumes",
		  $OID_BASE.".04"	=> "amount_snapshots",

		  $OID_BASE.".05.1.1"	=> "pool_status_index",
		  $OID_BASE.".06.1.1"	=> "arc_usage_index",
		  $OID_BASE.".07.1.1"	=> "arc_stats_index",
		  $OID_BASE.".08.1.1"	=> "vfs_iops_index",
		  $OID_BASE.".09.1.1"	=> "vfs_bandwidth_index",
		  $OID_BASE.".10.1.1"	=> "zil_stats_index",
		  $OID_BASE.".11.1.1"	=> "pool_device_status_index",
		  $OID_BASE.".12.1.1"	=> "dbuf_stats_index");

# These hashes are a mapping for the data hash key.

# OID_BASE.5 => zfsPoolStatusTable
my %keys_pools =     (#01  => index
		      "02" => "name",
		      "03" => "size",
		      "04" => "alloc",
		      "05" => "free",
		      "06" => "cap",
		      "07" => "dedup",
		      "08" => "health",
		      "09" => "altroot",
		      "10" => "usedbysnapshots",
		      "11" => "used");

# OID_BASE.6 => zfsARCUsageTable
my %keys_arc_usage = (#01  => index
		      "02" => "arc_meta_max",
		      "03" => "arc_meta_used",
		      "04" => "arc_meta_limit",
		      "05" => "c_max",
		      "06" => "size");

# OID_BASE.7 => zfsARCStatsTable
my %keys_arc_stats = (#01  => index
		      "02" => "hits",
		      "03" => "misses",
		      "04" => "demand_data_hits",
		      "05" => "demand_data_misses",
		      "06" => "demand_metadata_hits",
		      "07" => "demand_metadata_misses",
		      "08" => "prefetch_data_hits",
		      "09" => "prefetch_data_misses",
		      "10" => "prefetch_metadata_hits",
		      "11" => "prefetch_metadata_misses",
		      "12" => "l2_hits",
		      "13" => "l2_misses");

# OID_BASE.8 => zfsVFSIOPSTable
my %keys_vfs_iops =  (#01  => index
		      "02" => "name",
		      "03" => "oper_reads",
		      "04" => "oper_writes");

# OID_BASE.9 => zfsVFSThroughputTable
my %keys_vfs_bwidth =(#01  => index
		      "02" => "name",
		      "03" => "bandwidth_reads",
		      "04" => "bandwidth_writes");

# OID_BASE.10 => ZIL status values
my %keys_zil_stats = (#01  => index
		      "02" => "zil_commit_count",
		      "03" => "zil_commit_writer_count",
		      "04" => "zil_itx_count",
		      "05" => "zil_itx_indirect_count",
		      "06" => "zil_itx_indirect_bytes",
		      "07" => "zil_itx_copied_count",
		      "08" => "zil_itx_copied_bytes",
		      "09" => "zil_itx_needcopy_count",
		      "10" => "zil_itx_needcopy_bytes",
		      "11" => "zil_itx_metaslab_normal_count",
		      "12" => "zil_itx_metaslab_normal_bytes",
		      "13" => "zil_itx_metaslab_slog_count",
		      "14" => "zil_itx_metaslab_slog_bytes");

# OID_BASE.11 => Pool status values
my %keys_dev_stats = (#01  => index
		      "02" => "name",
		      "03" => "state",
		      "04" => "read",
		      "05" => "write",
		      "06" => "cksum");

# OID_BASE.12 => DBUF status values
my %keys_dbuf_stats =(#01  => index
		      "02" => "pool",
		      "03" => "objset",
		      "04" => "object",
		      "05" => "level",
		      "06" => "blkid",
		      "07" => "offset",
		      "08" => "dbsize",
		      "09" => "meta",
		      "10" => "state",
		      "11" => "dbholds",
		      "12" => "list",
		      "13" => "atype",
		      "14" => "index",
		      "15" => "flags",
		      "16" => "count",
		      "17" => "asize",
		      "18" => "access",
		      "19" => "mru",
		      "20" => "gmru",
		      "21" => "mfu",
		      "22" => "gmfu",
		      "23" => "l2",
		      "24" => "l2_dattr",
		      "25" => "l2_asize",
		      "26" => "l2_comp",
		      "27" => "aholds",
		      "28" => "dtype",
		      "29" => "btype",
		      "30" => "data_bs",
		      "31" => "meta_bs",
		      "32" => "bsize",
		      "33" => "lvls",
		      "34" => "dholds",
		      "35" => "blocks",
		      "36" => "dsize");
# }}}

# These hases are for the textual conventions in the MIB

# {{{ Textual conventions
# ZFSPoolStatusValue - Pool device status
my %pool_status = ('DEGRADED'	=> 1,
		   'FAULTED'	=> 2,
		   'OFFLINE'	=> 3,
		   'ONLINE'	=> 4,
		   'REMOVED'	=> 5,
		   'UNAVAIL'	=> 6);

# ZFSDbufTypeValue - DBUF [bd]type
my %dbuf_types = ('DMU_OT_NONE'			=>  0,
		  # General:
		  'DMU_OT_OBJECT_DIRECTORY'	=>  1,
		  'DMU_OT_OBJECT_ARRAY'		=>  2,
		  'DMU_OT_PACKED_NVLIST'	=>  3,
		  'DMU_OT_PACKED_NVLIST_SIZE'	=>  4,
		  'DMU_OT_BPOBJ'		=>  5,
		  'DMU_OT_BPOBJ_HDR'		=>  6,
		  # SPA:
		  'DMU_OT_SPACE_MAP_HEADER'	=>  7,
		  'DMU_OT_SPACE_MAP'		=>  8,
		  # ZIL:
		  'DMU_OT_INTENT_LOG'		=>  9,
		  # DMU:
		  'DMU_OT_DNODE'		=> 10,
		  'DMU_OT_OBJSET'		=> 11,
		  # DSL:
		  'DMU_OT_DSL_DIR'		=> 12,
		  'DMU_OT_DSL_DIR_CHILD_MAP'	=> 13,
		  'DMU_OT_DSL_DS_SNAP_MAP'	=> 14,
		  'DMU_OT_DSL_PROPS'		=> 15,
		  'DMU_OT_DSL_DATASET'		=> 16,
		  # ZPL:
		  'DMU_OT_ZNODE'		=> 17,
		  'DMU_OT_OLDACL'		=> 18,
		  'DMU_OT_PLAIN_FILE_CONTENTS'	=> 19,
		  'DMU_OT_DIRECTORY_CONTENTS'	=> 20,
		  'DMU_OT_MASTER_NODE'		=> 21,
		  'DMU_OT_UNLINKED_SET'		=> 22,
		  # ZVOL:
		  'DMU_OT_ZVOL'			=> 23,
		  'DMU_OT_ZVOL_PROP'		=> 24,
		  # other; for testing only!
		  'DMU_OT_PLAIN_OTHER'		=> 25,
		  'DMU_OT_UINT64_OTHER'		=> 26,
		  'DMU_OT_ZAP_OTHER'		=> 27,
		  # New object types:
		  'DMU_OT_ERROR_LOG'		=> 28,
		  'DMU_OT_SPA_HISTORY'		=> 29,
		  'DMU_OT_SPA_HISTORY_OFFSETS'	=> 30,
		  'DMU_OT_POOL_PROPS'		=> 31,
		  'DMU_OT_DSL_PERMS'		=> 32,
		  'DMU_OT_ACL'			=> 33,
		  'DMU_OT_SYSACL'		=> 34,
		  'DMU_OT_FUID'			=> 35,
		  'DMU_OT_FUID_SIZE'		=> 36,
		  'DMU_OT_NEXT_CLONES'		=> 37,
		  'DMU_OT_SCAN_QUEUE'		=> 38,
		  'DMU_OT_USERGROUP_USED'	=> 39,
		  'DMU_OT_USERGROUP_QUOTA'	=> 40,
		  'DMU_OT_USERREFS'		=> 41,
		  'DMU_OT_DDT_ZAP'		=> 42,
		  'DMU_OT_DDT_STATS'		=> 43,
		  'DMU_OT_SA'			=> 44,
		  'DMU_OT_SA_MASTER_NODE'	=> 45,
		  'DMU_OT_SA_ATTR_REGISTRATION'	=> 46,
		  'DMU_OT_SA_ATTR_LAYOUTS'	=> 47,
		  'DMU_OT_SCAN_XLATE'		=> 48,
		  'DMU_OT_DEDUP'		=> 49,
		  'DMU_OT_DEADLIST'		=> 50,
		  'DMU_OT_DEADLIST_HDR'		=> 51,
		  'DMU_OT_DSL_CLONES'		=> 52,
		  'DMU_OT_BPOBJ_SUBOBJ'		=> 53,
		  'UNKNOWN'			=> 196);

# ZFSDbufL2CompValue - DBUF l2_comp
my %dbuf_l2comp = ('ZIO_COMPRESS_INHERIT'	=>  0,
		   'ZIO_COMPRESS_ON'		=>  1,
		   'ZIO_COMPRESS_OFF'		=>  2,
		   'ZIO_COMPRESS_LZJB'		=>  3,
		   'ZIO_COMPRESS_EMPTY'		=>  4,
		   'ZIO_COMPRESS_GZIP_1'	=>  5,
		   'ZIO_COMPRESS_GZIP_2'	=>  6,
		   'ZIO_COMPRESS_GZIP_3'	=>  7,
		   'ZIO_COMPRESS_GZIP_4'	=>  8,
		   'ZIO_COMPRESS_GZIP_5'	=>  9,
		   'ZIO_COMPRESS_GZIP_6'	=> 10,
		   'ZIO_COMPRESS_GZIP_7'	=> 11,
		   'ZIO_COMPRESS_GZIP_8'	=> 12,
		   'ZIO_COMPRESS_GZIP_9'	=> 13,
		   'ZIO_COMPRESS_ZLE'		=> 14,
		   'ZIO_COMPRESS_LZ4'		=> 15,
		   'ZIO_COMPRESS_FUNCTION'	=> 16);
# }}}

# {{{ Some global data variables
my(%POOLS, %DATASETS, %SNAPSHOTS, %VOLUMES, %STATUS_INFO);
my($POOLS, $DATASETS, $SNAPSHOTS, $VOLUMES, $DEVICES);
my($oid, $arg, $TYPE_STATUS, %ARC, %VFS, %ZIL, %DBUFS);
# }}}

# handle a SIGALRM - reload information/statistics and
# config file.
$SIG{'ALRM'} = \&load_information;
# }}}

# ====================================================
# =====    R E T R E I V E  F U N C T I O N S    =====

# {{{ ZFS Get Property
sub zfs_get_prop {
    my $prop = shift;
    my $fs = shift;
    my($val, %vals);

    open(ZFS, "$CFG{'ZFS'} get -H -oproperty,value $prop '$fs' |") ||
	die("Can't call $CFG{'ZFS'}, $!\n");
    while(! eof(ZFS)) {
	$val = <ZFS>;
	chomp($val);
	my($p, $v) = split('	', $val);

	$vals{$p} = $v;
    }
    close(ZFS);

    return(%vals);
}
# }}}

# {{{ ZPOOL Get Property
sub zpool_get_prop {
    my $prop = shift;
    my $pool = shift;

    my $val = (split('	', `$CFG{'ZPOOL'} get $prop $pool | egrep ^$pool"`))[3];
    print $val;
}
# }}}

# {{{ Get all pools and their data
sub get_pools {
    my(%pools);
    my $pools = 0;

    open(ZPOOL, "$CFG{'ZPOOL'} list |") ||
	die("Can't call $CFG{'ZPOOL'}, $!");

    # First line is column
    my $line = <ZPOOL>;
    chomp($line);
    my @cols = split(' ', $line);

    # Make the columns lower case
    for(my $i=0; $cols[$i]; $i++) {
	$cols[$i] = lc($cols[$i]);
    }

    # Get pools and the 'zpool list' data.
    while(! eof(ZPOOL)) {
	my $pool = <ZPOOL>;
	return(0, ()) if($pool eq 'no pools available');

	my $pool_name = (split(' ', $pool))[0];

	my @data = split(' ', $pool);

	for(my $i=0; $cols[$i]; $i++) {
	    $pools{$pool_name}{$cols[$i]} = $data[$i];
	}

	$pools++;
    }
    close(ZPOOL);

    # Use 'zfs get' to get the exact size of the pool(s).
    foreach my $pool_name (keys %pools) {
	my %data = &zpool_get_sizes($pool_name);
	foreach my $key (keys %data) {
	    $pools{$pool_name}{$key} = $data{$key};
	}

	chop($pools{$pool_name}{'cap'});
	chop($pools{$pool_name}{'dedup'});
    }

    return($pools, %pools);
}
# }}}

# {{{ Get pool sizes
sub zpool_get_sizes {
    my $pool = shift;
    my($prop, $val, %data, %rets);

    open(ZFS, "$CFG{'ZFS'} get -H -oproperty,value -p used,available,referenced $pool |") ||
	die("Can't call $CFG{'ZFS'}, $!");
    while(! eof(ZFS)) {
	my $line = <ZFS>; chomp($line);
	($prop, $val) = split('	', $line);
	$data{$prop} = $val;
    }
    close(ZFS);

    # size  => used + avail + refer
    # alloc => used
    # free  => size - alloc
    $rets{'size'}  = $data{'used'} + $data{'available'} + $data{'referenced'};
    $rets{'alloc'} = $data{'used'};
    $rets{'free'}  = $rets{'size'} - $rets{'alloc'};

    return(%rets);
}
# }}}

# {{{ Get all pool status
sub zpool_get_status {
    my($pool, $state, $vdev, %status, $devices);
    $devices = 0;

    open(ZPOOL, "$CFG{'ZPOOL'} status |") ||
	die("Can't call zpool, $!");
    while(! eof(ZPOOL)) {
	my $zpool = <ZPOOL>;
	chomp($zpool);

	next if ($zpool =~ /^$/ || $zpool =~ /^errors: /);

	if ($zpool =~ /^  pool: /) {
	    $pool =  $zpool;
	    $pool =~ s/.* //;

	    # Start from scratch - start of a pool status
	    undef($state);
	    undef($vdev);

	    next;
	} elsif ($zpool =~ /^ state: /) {
	    $state =  $zpool;
	    $state =~ s/.* //;

	    # Skip to the interesting bit (first VDEV)
	    while (! eof(ZPOOL)) {
		$zpool = <ZPOOL>;

		if ($zpool =~ /NAME.*STATE.*READ.*WRITE.*CKSUM/) {
		    last;
		}
	    }

	    # Next line after the header is the pool status line
	    $zpool = <ZPOOL>;
	    chomp($zpool);

	    my $dev = (split(' ', $zpool))[0];

	    ($status{$dev}{'name'}, $status{$dev}{'state'}, $status{$dev}{'read'},
	     $status{$dev}{'write'}, $status{$dev}{'cksum'}) = split(' ', $zpool);

	    # Translate the status to a number according to %pool_status
	    foreach my $stat (keys %pool_status) {
		if ($status{$dev}{'state'} eq $stat) {
		    $status{$dev}{'state'} = $pool_status{$stat};
		}
	    }

	    $devices++;
	} elsif ($zpool =~ /raid|mirror/) {
	    $zpool =~ s/^	//; # Remove initial tab to get something to split on
	    $vdev = (split(' ', $zpool))[0];

	    # Get next line - the dev
	    $zpool = <ZPOOL>;
	    chomp($zpool);
	} elsif ($zpool =~ /spares|cache|logs/) {
	    # For spares and caches - ignore. They aren't online, so no read/write/cksum values
	    undef($vdev); # Don't reuse the previous vdev value.
	    next;
	}

	if ($zpool && $state && $vdev) {
	    $zpool =~ s/^	//; # Remove initial tab to get something to split on
	    my $dev = (split(' ', $zpool))[0];

	    ($status{$dev}{'name'}, $status{$dev}{'state'}, $status{$dev}{'read'},
	     $status{$dev}{'write'}, $status{$dev}{'cksum'}) = split(' ', $zpool);

	    # Translate the status to a number according to %pool_status
	    foreach my $stat (keys %pool_status) {
		if ($status{$dev}{'state'} eq $stat) {
		    $status{$dev}{'state'} = $pool_status{$stat};
		}
	    }

	    $devices++;
	}
    }

    close(ZPOOL);

    return($devices, %status);
}
# }}}

# {{{ Get all filesystems/volumes/snapshots
sub get_list {
    my $type = shift;

    my(%LIST);
    my $datasets = 0;

    open(ZFS, "$CFG{'ZFS'} list -H -t$type 2> /dev/null |") ||
	die("Can't call $CFG{'ZFS'}, $!");
    while(! eof(ZFS)) {
	my $fs = <ZFS>;
	chomp($fs);

	return(0, ()) if($fs eq 'no datasets available');
	my $dset_name = (split('	', $fs))[0];

	($LIST{$dset_name}{'name'},  $LIST{$dset_name}{'used'},
	 $LIST{$dset_name}{'avail'}, $LIST{$dset_name}{'refer'},
	 $LIST{$dset_name}{'mountpoint'}) = split('	', $fs);

	$datasets++;
    }
    close(ZFS);

    return($datasets, %LIST);
}
# }}}

# {{{ Get 'used*' in all filesystems and volumes
sub get_used {
    my $pool = shift;
    my $prop = shift;

    my %total;
    my %all = (%DATASETS, %VOLUMES);

    foreach my $fs (sort keys %all) {
	next if($fs !~ /^$pool/);

	my %vals = &zfs_get_prop($prop, $fs);
	foreach my $key (keys %vals) {
	    my $size = &human_to_bytes($vals{$key});
	    $total{$key} += $size;
	}
    }

    return(%total);
}
# }}}

# {{{ Get ARC status
sub get_arc_status {
    my(%arc, @all_arc_keys, $key) = ( );

    # Put together an array with ALL the info we want
    # from the arcstats file...
    foreach $key (keys %keys_arc_usage) {
	push(@all_arc_keys, $keys_arc_usage{$key});
    }
    foreach $key (keys %keys_arc_stats) {
	push(@all_arc_keys, $keys_arc_stats{$key});
    }

    # Open arcstats file and get what we want...
    open(ARCSTATS, "$CFG{'KSTATDIR'}/arcstats") ||
	die("Can't open $CFG{'KSTATDIR'}/arcstats, $!\n");
    my $line = <ARCSTATS>; $line = <ARCSTATS>; # Just get the two first dumy lines
    while(! eof(ARCSTATS)) {
	my $line = <ARCSTATS>;
	chomp($line);

	my($name, $type, $data) = split(' ', $line);
	for(my $i = 0; $all_arc_keys[$i]; $i++) {
	    if($name eq $all_arc_keys[$i]) {
		$arc{$all_arc_keys[$i]} = $data;
	    }
	}
    }
    close(ARCSTATS);

    return(%arc);
}
# }}}

# {{{ Get VFS IOPS and Throughput stats
sub get_vfs_stats {
    my($dummy, $line, $name, %vfs);

    open(ZPOOL, "$CFG{'ZPOOL'} iostat 2> /dev/null |") ||
	die("Can't call $CFG{'ZPOOL'}, $!\n");
    while(! eof(ZPOOL)) {
	$line = <ZPOOL>;
	chomp($line);

	$name = (split(' ', $line))[0];
	next if(($name eq 'capacity') || ($name eq 'pool') ||
		($name eq '----------'));

	foreach my $pool_name (sort keys %POOLS) {
	    if($name eq $pool_name) {
		$vfs{$pool_name}{'name'} = $pool_name;
		($dummy, $dummy, $dummy,
		 $vfs{$pool_name}{'oper_reads'},
		 $vfs{$pool_name}{'oper_writes'},
		 $vfs{$pool_name}{'bandwidth_reads'},
		 $vfs{$pool_name}{'bandwidth_writes'}) =
		     split(' ', $line);
	    }
	}
    }
    close(ZPOOL);

    return(%vfs);
}
# }}}

# {{{ Get ZIL status
sub get_zil_stats {
    my(%zil, @all_zil_keys, $key) = ( );

    # Put together an array with ALL the info we want
    # from the arcstats file...
    foreach $key (keys %keys_zil_stats) {
	push(@all_zil_keys, $keys_zil_stats{$key});
    }

    # Open zil file and get what we want...
    open(ZILSTATS, "$CFG{'KSTATDIR'}/zil") ||
	die("Can't open $CFG{'KSTATDIR'}/zil, $!\n");
    my $line = <ZILSTATS>; $line = <ZILSTATS>; # Just get the two first dummy lines
    while(! eof(ZILSTATS)) {
	my $line = <ZILSTATS>;
	chomp($line);

	my($name, $type, $data) = split(' ', $line);
	for(my $i = 0; $all_zil_keys[$i]; $i++) {
	    if($name eq $all_zil_keys[$i]) {
		$zil{$all_zil_keys[$i]} = $data;
	    }
	}
    }
    close(ARCSTATS);

    return(%zil);
}
# }}}

# {{{ Get DBUF stats
sub get_dbufs_stats {
    my($linenr, $line, @colnames, @data, %data, %dbufs) = ( );

    # Open zil file and get what we want...
    open(DBUFSSTATS, "$CFG{'KSTATDIR'}/dbufs") ||
	die("Can't open $CFG{'KSTATDIR'}/dbufs, $!\n");

    # Just get the two first dummy lines
    for(my $i=0; $i <= 1; $i++) {
	$line = <DBUFSSTATS>;
    }

    # The column names line
    $line = <DBUFSSTATS>;
    $line =~ s/\|//g;
    @colnames = split(' ', $line);

    $linenr = 0;
    while(! eof(DBUFSSTATS)) {
	$line = <DBUFSSTATS>;
	chomp($line);
	$line =~ s/\|//g;

	@data = split(' ', $line);
	my $pool_name = $data[0];

	for(my $i = 0; $colnames[$i]; $i++) {
	    $data{$pool_name}{$linenr}{$colnames[$i]} = $data[$i];
	}

	$linenr++;
    }
    close(DBUFSSTATS);

    # Sort by pool name and flatten hash
    my $j = 0;
    foreach my $pool_name (sort keys %data) {
	foreach my $nr (sort {$a <=> $b} keys %{$data{$pool_name}}) {
	    foreach my $col (keys %{$data{$pool_name}{$nr}}) {
		my $k = sprintf("%02d", $j);
		$dbufs{$k}{$col} = $data{$pool_name}{$nr}{$col};
	    }
	    $j++;
	}
    }

    return(%dbufs);
}
# }}}

# ====================================================
# =====       P R I N T  F U N C T I O N S       =====

# {{{ OID_BASE.1.0              Output total number of pools
sub print_amount_pools {
    if($CFG{'DEBUG'}) {
	debug(0, "=> OID_BASE.zfsTotalPools.0\n") if($CFG{'DEBUG'} > 1);
	debug(0, "$OID_BASE.1.0 = $DATASETS\n");
    }

    debug(1, "$OID_BASE.1.0\n");
    debug(1, "integer\n");
    debug(1, "$POOLS\n");

    debug(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return 1;
}
# }}}

# {{{ OID_BASE.2.0              Output total number of datasets
sub print_amount_datasets {
    if($CFG{'DEBUG'}) {
	debug(0, "=> OID_BASE.zfsTotalDatasets.0\n") if($CFG{'DEBUG'} > 1);
	debug(0, "$OID_BASE.2.0 = $DATASETS\n");
    }

    debug(1, "$OID_BASE.2.0\n");
    debug(1, "integer\n");
    debug(1, "$DATASETS\n");

    debug(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return 1;
}
# }}}

# {{{ OID_BASE.3.0              Output total number of volumes
sub print_amount_volumes {
    if($CFG{'DEBUG'}) {
	debug(0, "=> OID_BASE.zfsTotalVolumes.0\n") if($CFG{'DEBUG'} > 1);
	debug(0, "$OID_BASE.3.0 = $VOLUMES\n");
    }

    debug(1, "$OID_BASE.3.0\n");
    debug(1, "integer\n");
    debug(1, "$VOLUMES\n");

    debug(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return 1;
}
# }}}

# {{{ OID_BASE.4.0              Output total number of snapshots
sub print_amount_snapshots {
    if($CFG{'DEBUG'}) {
	debug(0, "=> OID_BASE.zfsTotalSnapshots.0\n") if($CFG{'DEBUG'} > 1);
	debug(0, "$OID_BASE.4.0 = $SNAPSHOTS\n");
    }

    debug(1, "$OID_BASE.4.0\n");
    debug(1, "integer\n");
    debug(1, "$SNAPSHOTS\n");

    debug(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return 1;
}
# }}}


# {{{ OID_BASE.5.1.1.x          Output pool status index
sub print_pool_status_index {
    my $nr = shift;

    return(print_generic_complex_table_index($nr,
		"zfsPoolStatusTable.zfsPoolStatusEntry",
		"zfsPoolName", "zfsPoolStatusIndex",
		"5", \%keys_pools, \%POOLS));
}
# }}}

# {{{ OID_BASE.5.1.X.x          Output pool status information
sub print_pool_status_info {
    my $nr = shift;

    return(print_generic_complex_table_info($nr,
		"zfsPoolStatusTable.zfsPoolStatusEntry",
		"zfsPoolName", "5", \%keys_pools, \%POOLS));
}
# }}}


# {{{ OID_BASE.6.1.1.x          Output ARC usage index
sub print_arc_usage_index {
    my $nr = shift;

    return(print_generic_simple_table_index($nr, "zfsARCUsageTable.zfsARCUsageEntry",
			       "zfsARCUsageIndex", "6", \%keys_arc_usage));
}
# }}}

# {{{ OID_BASE.6.1.X.x          Output ARC usage information
sub print_arc_usage_info {
    my $nr = shift;

    return(print_generic_simple_table_info($nr, "zfsARCUsageTable.zfsARCUsageEntry",
			      "6", \%keys_arc_usage, \%ARC));
}
# }}}


# {{{ OID_BASE.7.1.1.x          Output ARC status index
sub print_arc_stats_index {
    my $nr = shift;

    return(print_generic_simple_table_index($nr, "zfsARCStatsTable.zfsARCStatsEntry",
			       "zfsARCStatsIndex", "7", \%keys_arc_stats));
}
# }}}

# {{{ OID_BASE.7.1.X.x          Output ARC status information
sub print_arc_stats_info {
    my $nr = shift;

    return(print_generic_simple_table_info($nr, "zfsARCStatsTable.zfsARCStatsEntry",
			      "7", \%keys_arc_stats, \%ARC));
}
# }}}


# {{{ OID_BASE.8.1.1.x          Output VFS IOPS index
sub print_vfs_iops_index {
    my $nr = shift;

    return(print_generic_complex_table_index($nr,
		"zfsVFSIOPSTable.zfsVFSIOPSEntry",
		"zfsPoolName", "zfsVFSIOPSIndex",
		"8", \%keys_vfs_iops, \%VFS));
}
# }}}

# {{{ OID_BASE.8.1.X.x          Output VFS IOPS information
sub print_vfs_iops_info {
    my $nr = shift;

    return(print_generic_complex_table_info($nr,
		"zfsVFSIOPSTable.zfsVFSIOPSEntry",
		"zfsPoolName", "8", \%keys_vfs_iops, \%VFS));
}
# }}}


# {{{ OID_BASE.9.1.1.x          Output VFS Bandwidth index
sub print_vfs_bandwidth_index {
    my $nr = shift;

    return(print_generic_complex_table_index($nr,
		"zfsVFSThroughputTable.zfsVFSThroughputEntry",
		"zfsPoolName", "zfsVFSThroughputIndex",
		"9", \%keys_vfs_bwidth, \%VFS));
}
# }}}

# {{{ OID_BASE.9.1.1.x          Output VFS Bandwidth information
sub print_vfs_bandwidth_info {
    my $nr = shift;

    return(print_generic_complex_table_info($nr,
		"zfsVFSThroughputTable.zfsVFSThroughputEntry",
		"zfsPoolName", "9", \%keys_vfs_bwidth, \%VFS));
}
# }}}


# {{{ OID_BASE.10.1.1.x         Output ZIL status index
sub print_zil_stats_index {
    my $nr = shift;

    return(print_generic_simple_table_index($nr, "zfsZILStatsTable.zfsZILStatsEntry",
			       "zfsZILStatsIndex", "10", \%keys_zil_stats));
}
# }}}

# {{{ OID_BASE.10.1.X.x         Output ZIL status information
sub print_zil_stats_info {
    my $nr = shift;

    return(print_generic_simple_table_info($nr, "zfsZILStatsTable.zfsZILStatsEntry",
			      "10", \%keys_zil_stats, \%ZIL));
}
# }}}


# {{{ OID_BASE.11.1.1.x         Output pool device status index
sub print_pool_device_status_index {
    my $nr = shift;

    return(print_generic_complex_table_index($nr,
		"zfsPoolDevStatusTable.zfsPoolDevStatusEntry",
		"zfsPoolDevName", "zfsPoolDevStatusIndex",
		"11", \%keys_dev_stats, \%STATUS_INFO));
}
# }}}

# {{{ OID_BASE.11.1.X.x         Output pool device status information
sub print_pool_device_status_info {
    my $nr = shift;

    return(print_generic_complex_table_info($nr,
		"zfsPoolDevStatusTable.zfsDevPoolStatusEntry",
		"zfsPoolDevName", "11", \%keys_dev_stats, \%STATUS_INFO));
}
# }}}


# {{{ OID_BASE.12.1.1.x         Output DBUF status index
sub print_dbuf_stats_index {
    my $nr = shift;

    return(print_generic_complex_table_index($nr,
		"zfsDbufStatsTable.zfsDbufStatsEntry",
		"zfsDbufPoolName", "zfsDbufStatsIndex",
		"12", \%keys_dbuf_stats, \%DBUFS));
}
# }}}

# {{{ OID_BASE.12.1.X.x         Output DBUF status information
sub print_dbuf_stats_info {
    my $nr = shift;

    return(print_generic_complex_table_info($nr,
		"zfsDbufStatsTable.zfsDbufStatsEntry",
		"zfsDbufPoolName", "12", \%keys_dbuf_stats, \%DBUFS));
}
# }}}


# {{{ Generic 'print complex index' for OID_BASE.{5,8,9,11,12}
# Used with double level hashes - index
sub print_generic_complex_table_index {
    my $value_no   = shift;
    my $legend     = shift;
    my $legend_key = shift;
    my $index_key  = shift;
    my $oid        = shift;
    my %keys       = %{shift()};
    my %data       = %{shift()};

    my $success = 0;
    debug(0, "=>> OID_BASE.$legend.$index_key\n") if($CFG{'DEBUG'} > 1);

    if(defined($value_no)) {
	# {{{ Specific pool name
	foreach my $key_nr (sort keys %keys) {
	    my $value = sprintf("%02d", $TYPE_STATUS+1); # This is the index - offset one!
	    if($key_nr == $value) {
		my $key_name = $keys{$key_nr};
		$key_nr =~ s/^0//;
		$key_nr -= 1; # This is the index - offset one!
		debug(0, "=> OID_BASE.$legend.$key_name.$legend_key\n") if($CFG{'DEBUG'} > 1);
		
		my $pool_nr = 1;
		foreach my $pool_name (sort keys %data) {
		    if($pool_nr == $value_no) {
			debug(0, "$OID_BASE.$oid.1.$key_nr.$pool_nr = $pool_nr\n") if($CFG{'DEBUG'});
			
			debug(1, "$OID_BASE.$oid.1.$key_nr.$pool_nr\n");
			debug(1, "integer\n");
			debug(1, "$pool_nr\n");
			
			return(1);
		    }

		    $pool_nr++;
		}
	    }
	}
# }}}
    } else {
	# {{{ ALL pool values
	my $pool_nr = 1;
	foreach my $pool_name (sort keys %data) {
	    debug(0, "$OID_BASE.$oid.1.1.$pool_nr = $pool_nr\n") if($CFG{'DEBUG'});
	    
	    debug(1, "$OID_BASE.$oid.1.1.$pool_nr\n");
	    debug(1, "integer\n");
	    debug(1, "$pool_nr\n");
	    
	    $success = 1;
	    $pool_nr++;
	}
# }}}
    }

    debug(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return $success;
}
# }}}

# {{{ Generic 'print complex info'  for OID_BASE.{5,8,9,11,12}
# Used with double level hashes - values
sub print_generic_complex_table_info {
    my $value_no   = shift; # Row number
    my $legend     = shift;
    my $legend_key = shift;
    my $oid        = shift;
    my %keys       = %{shift()};
    my %data       = %{shift()};

    my $success = 0;

    if(defined($value_no)) {
	# {{{ Specific value
	foreach my $key_nr (sort keys %keys) {
	    my $value = sprintf("%02d", $TYPE_STATUS);
	    if($key_nr == $value) {
		my $key_name = $keys{$key_nr};
		$key_nr =~ s/^0//;
		debug(0, "=> OID_BASE.$legend.$key_name.$legend_key\n") if($CFG{'DEBUG'} > 1);

		my $pool_nr = 1;
		foreach my $pool_name (sort keys %data) {
		    if($pool_nr == $value_no) {
			# Just to get some pretty debugging output - translate value into textual conversion
			my $translated_value;
			if($key_name eq 'btype' or $key_name eq 'dtype') {
			    foreach my $key (keys %dbuf_types) {
				if($dbuf_types{$key} == $data{$pool_name}{$key_name}) {
				    $translated_value = $key;
				    last;
				}
			    }

			    if(!defined($translated_value)) {
				$translated_value = $data{$pool_name}{$key_name};
			    }
			} elsif($key_name eq 'l2_comp') {
			    foreach my $key (keys %dbuf_l2comp) {
				if($dbuf_l2comp{$key} == $data{$pool_name}{$key_name}) {
				    $translated_value = $key;
				    last;
				}
			    }
			} else {
			    $translated_value = $data{$pool_name}{$key_name};
			}
			debug(0, "$OID_BASE.$oid.1.$key_nr.$pool_nr = $translated_value\n") if($CFG{'DEBUG'});

			debug(1, "$OID_BASE.$oid.1.$key_nr.$pool_nr\n");
			if(($key_name eq 'altroot') ||
			   ($key_name eq 'name')    ||
			   ($key_name eq 'dedup')   ||
			   ($key_name eq 'flags')   ||
			   ($key_name eq 'pool'))
			{
			    debug(1, "string\n");
			} elsif(($key_name eq 'oper_reads') || ($key_name eq 'oper_writes') ||
				($key_name eq 'bandwidth_reads') || ($key_name eq 'bandwidth_writes'))
			{
			    debug(1, "counter\n");
			} else {
			    debug(1, "integer\n");
			}

			if($key_name eq 'health') {
			    my $stat = $data{$pool_name}{$key_name};
			    debug(1, $pool_status{$stat}."\n");
			} else {
			    debug(1, $data{$pool_name}{$key_name}."\n");
			}

			return(1);
		    }

		    $pool_nr++;
		}
	    }
	}
# }}}
    } else {
	# {{{ ALL values
	foreach my $key_nr (sort keys %keys) {
	    my $key_name = $keys{$key_nr};
	    $key_nr =~ s/^0//;
	    debug(0, "=> OID_BASE.$legend.$key_name.$legend_key\n") if($CFG{'DEBUG'} > 1);

	    my $pool_nr = 1;
	    foreach my $pool_name (sort keys %data) {
		# Just to get some pretty debugging output - translate value into textual conversion
		my $translated_value;
		if($key_name eq 'btype' or $key_name eq 'dtype') {
		    foreach my $key (keys %dbuf_types) {
			if($dbuf_types{$key} == $data{$pool_name}{$key_name}) {
			    $translated_value = $key;
			    last;
			}
		    }

		    if(!defined($translated_value)) {
			$translated_value = $data{$pool_name}{$key_name};
		    }
		} elsif($key_name eq 'l2_comp') {
		    foreach my $key (keys %dbuf_l2comp) {
			if($dbuf_l2comp{$key} == $data{$pool_name}{$key_name}) {
			    $translated_value = $key;
			    last;
			}
		    }
		} else {
		    $translated_value = $data{$pool_name}{$key_name};
		}
		debug(0, "$OID_BASE.$oid.1.$key_nr.$pool_nr = $translated_value\n") if($CFG{'DEBUG'});
		
		debug(1, "$OID_BASE.$oid.1.$key_nr.$pool_nr\n");
		if(($key_name eq 'altroot') ||
		   ($key_name eq 'name')    ||
		   ($key_name eq 'dedup')   ||
		   ($key_name eq 'flags')   ||
		   ($key_name eq 'pool'))
		{
		    debug(1, "string\n");
		} elsif(($key_name eq 'oper_reads') || ($key_name eq 'oper_writes') ||
			($key_name eq 'bandwidth_reads') || ($key_name eq 'bandwidth_writes'))
		{
		    debug(1, "counter\n");
		} else {
		    debug(1, "integer\n");
		}

		if($key_name eq 'health') {
		    my $stat = $data{$pool_name}{$key_name};
		    debug(1, $pool_status{$stat}."\n");
		} else {
		    debug(1, $data{$pool_name}{$key_name}."\n");
		}

		$success = 1;
		$pool_nr++;
	    }

	    debug(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
	}
# }}}
    }

    return $success;
}
# }}}


# {{{ Generic 'print simple index' for OID_BASE.{6,7,10}
# Used with one level hases - index
sub print_generic_simple_table_index {
    my $nr         = shift;
    my $legend     = shift;
    my $legend_key = shift;
    my $oid        = shift;
    my %keys       = %{shift()};

    my $success = 0;
    debug(0, "=> OID_BASE.$legend.$legend_key\n") if($CFG{'DEBUG'} > 1);

    if(defined($nr)) {
	# {{{ Specific value
	foreach my $key_nr (sort keys %keys) {
	    my $value = sprintf("%02d", $TYPE_STATUS+1);
	    if($key_nr == $value) {
		my $key_name = $keys{$key_nr};
		$key_nr =~ s/^0//;
		$key_nr -= 1; # This is the index - offset one!
		debug(0, "$OID_BASE.$oid.1.1.$key_nr = $key_nr\n") if($CFG{'DEBUG'});
			
		debug(1, "$OID_BASE.$oid.1.1.$key_nr\n");
		debug(1, "integer\n");
		debug(1, "$key_nr\n");

		return(1);
	    }
	}
# }}}
    } else {
	# {{{ ALL values
	my $nr = 1;
	foreach my $name (sort keys %keys) {
	    debug(0, "$OID_BASE.$oid.1.1.$nr = $nr\n") if($CFG{'DEBUG'});
	    
	    debug(1, "$OID_BASE.$oid.1.1.$nr\n");
	    debug(1, "integer\n");
	    debug(1, "$nr\n");
	    
	    $success = 1;
	    $nr++;
	}
	debug(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});

	return($success);
# }}}
    }
}
# }}}

# {{{ Generic 'print simple info' for OID_BASE.{6,7,10}
# Used with one level hases - values
sub print_generic_simple_table_info {
    my $value_no = shift;
    my $legend   = shift;
    my $oid      = shift;
    my %keys     = %{shift()};
    my %data     = %{shift()};

    my $success = 0;

    if(defined($value_no)) {
	# {{{ Specific value
	foreach my $key_nr (sort keys %keys) {
	    my $value = sprintf("%02d", $TYPE_STATUS);
	    if($key_nr == $value) {
		my $key_name = $keys{$key_nr};
		$key_nr =~ s/^0//;
		debug(0, "=> OID_BASE.$legend.$key_name.$value_no\n") if($CFG{'DEBUG'} > 1);
		debug(0, "$OID_BASE.$oid.1.$key_nr.$value_no = ".$data{$key_name}."\n") if($CFG{'DEBUG'});
			
		debug(1, "$OID_BASE.$oid.1.$key_nr.$value_no\n");
		debug(1, "counter\n");
		debug(1, $data{$key_name}."\n");

		return(1);
	    }
	}
# }}}
    } else {
	# {{{ ALL values
	my $key_ctr = 1;
	foreach my $key_nr (sort keys %keys) {
	    my $key_name = $keys{$key_nr};
	    $key_nr =~ s/^0//;
	    debug(0, "=> OID_BASE.$legend.$key_name.1\n") if($CFG{'DEBUG'} > 1);
	    debug(0, "$OID_BASE.$oid.1.$key_ctr.1 = $data{$key_name}\n") if($CFG{'DEBUG'});

	    debug(1, "$OID_BASE.$oid.1.$key_ctr.1\n");
	    debug(1, "counter\n");
	    debug(1, $data{$key_name}."\n");

	    $success = 1;
	    $key_ctr++;

	    debug(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
	}

	return $success;
# }}}
    }
}
# }}}

# ====================================================
# =====        M I S C  F U N C T I O N S        =====

# {{{ Call function with option
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
    $func_arg =  '' if(!defined($func_arg));

    debug(0, "=> call_print($func_nr, $func_arg)\n") if($CFG{'DEBUG'} > 3);
    my $func = $functions{$func_nr};
    if($func) {
	$function = "print_".$func;
    } else {
	foreach my $oid (sort keys %functions) {
	    # Take the very first match
	    if($oid =~ /^$func_nr/) {
		debug(0, "=> '$oid =~ /^$func_nr/'\n") if($CFG{'DEBUG'} > 2);
		$function = "print_".$functions{$oid};
		last;
	    }
	}
    }

    if(defined($function)) {
	debug(0, "=> Calling function '$function($func_arg)'\n") if($CFG{'DEBUG'} > 2);
	
	$function = \&{$function}; # Because of 'use strict' above...
	&$function($func_arg);
    } else {
	return 0;
    }
}
# }}}

# {{{ Load all information needed
sub load_information {
    # ---------------------------------
    # Load configuration file and connect to SQL server.
    %CFG = get_config($CFG_FILE);

    # ---------------------------------
    # Get number of pools and their name
    ($POOLS,     %POOLS)     = &get_pools();

    # ---------------------------------
    # Get the pool status (read/write/cksum info)
    ($DEVICES, %STATUS_INFO) = &zpool_get_status();

    # ---------------------------------
    # Get filesystems, snapshots and volumes in each pool
    ($DATASETS,  %DATASETS)  = &get_list('filesystem');
    ($VOLUMES,   %VOLUMES)   = &get_list('volume');
    ($SNAPSHOTS, %SNAPSHOTS) = &get_list('snapshot');

    # ---------------------------------
    # Get interesting properties for each filesystem+volume in each pool
    # Currently only 'usedbysnapshots' and 'used' is used in the MIB.
    my $props = "usedbysnapshots,usedbydataset,used,".	
	"usedbychildren,usedbyrefreservation,".
	"referenced,written,logicalused,".
	"logicalreferenced";
    my @props_array = split(',', $props);

    foreach my $pool (keys %POOLS) {
	my %values = &get_used($pool, $props);

	for(my $i = 0; $props_array[$i]; $i++) {
	    $POOLS{$pool}{$props_array[$i]} = $values{$props_array[$i]};
	}
    }

    # ---------------------------------
    # Get ARC/L2ARC status information
    %ARC = &get_arc_status();

    # ---------------------------------
    # Get VFS IOPS and Bandwidth information
    %VFS = &get_vfs_stats();

    # ---------------------------------
    # Get ZIL status information
    %ZIL = &get_zil_stats();

    # ---------------------------------
    # Get DBUFS status information
# Could be dangerous - see https://github.com/zfsonlinux/zfs/issues/2495
#    %DBUFS = &get_dbufs_stats();

    # ---------------------------------
    # Schedule an alarm once every ten minute to re-read information.
    alarm(60*$CFG{'RELOAD'});
}
# }}}

# {{{ Convert human readable size to raw bytes
sub human_to_bytes {
    my $value = shift;

    my $len = length($value);
    my $size_char = substr($value, $len-1);

    my $size = $value;
    $size =~ s/$size_char//;
    
    if($size_char =~ /^[Kk]$/) {
	$size *= 1024;
    } elsif($size_char =~ /^[Mm]$/) {
	$size *= 1024 * 1024;
    } elsif($size_char =~ /^[Gg]$/) {
	$size *= 1024 * 1024 * 1024;
    } elsif($size_char =~ /^[Tt]$/) {
	$size *= 1024 * 1024 * 1024 * 1024;
    } elsif($size_char =~ /^[Pp]$/) {
	$size *= 1024 * 1024 * 1024 * 1024 * 1024;
    } else {
	$size = $value;
    }

    return($size);
}
# }}}

# {{{ Get next value from a set of input
sub get_next_oid {
    my @tmp = @_;

    output_extra_debugging(@tmp) if($CFG{'DEBUG'} > 3);

    # next1 => Base OID to use in call
    # next2 => next1.next2 => Full OID to retreive
    # next3 => Pool number (OID_BASE.5) or ....
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
    if(($tmp[0] == 5)  || ($tmp[0] == 8) || ($tmp[0] == 9) ||
       ($tmp[0] == 11) || ($tmp[0] == 12)) {
	$TYPE_STATUS = $tmp[2];
    } else {
	if($tmp[2] == 1) {
	    $TYPE_STATUS = $tmp[3];
	} else {
	    $TYPE_STATUS = $tmp[2];
	}
    }

    return($next1, $next2, $next3);
}
# }}}

# ====================================================
# =====          P R O C E S S  A R G S          =====

debug(0, "=> OID_BASE => '$OID_BASE'\n") if($CFG{'DEBUG'});

# {{{ Go through the argument(s) passed to the program
my $ALL = 0;
for(my $i=0; $ARGV[$i]; $i++) {
    if($ARGV[$i] eq '--help' || $ARGV[$i] eq '-h' || $ARGV[$i] eq '?' ) {
	help();
	exit 1;
    } elsif($ARGV[$i] eq '--all' || $ARGV[$i] eq '-a') {
	$ALL = 1;
    } else {
	print "Unknown option '",$ARGV[$i],"'\n";
	help();
	exit 1;
    }
}
# }}}

# Load information - make sure we get latest info available
&load_information();
	
if($ALL) {
    # {{{ Output the whole MIB tree - used mainly/only for debugging purposes
    $functions{$OID_BASE.".05.1.2"} = "pool_status_info";
    $functions{$OID_BASE.".06.1.2"} = "arc_usage_info";
    $functions{$OID_BASE.".07.1.2"} = "arc_stats_info";
    $functions{$OID_BASE.".08.1.2"} = "vfs_iops_info";
    $functions{$OID_BASE.".09.1.2"} = "vfs_bandwidth_info";
    $functions{$OID_BASE.".10.1.2"} = "zil_stats_info";
    $functions{$OID_BASE.".11.1.2"} = "pool_device_status_info";
    $functions{$OID_BASE.".12.1.2"} = "dbuf_stats_info";

    foreach my $oid (sort keys %functions) {
	my $func = $functions{$oid};
	if($func) {
	    $func = \&{"print_".$func}; # Because of 'use strict' above...
	    &$func();
	}
    }
# }}} 
} else {
    # ALWAYS override the OID_BASE value since we're
    # running through the SNMP daemon!
    $OID_BASE = ".1.3.6.1.4.1.8767.2.6";

    # {{{ Rewrite the '%functions' array (replace OID_BASE with $OID_BASE)
    my($new_oid, %new_functions);
    foreach my $oid (sort keys %functions) {
	if($oid =~ /^OID_BASE/) {
	    $new_oid =  $oid;
	    $new_oid =~ s/OID_BASE/$OID_BASE/;
	    
	    $new_functions{$new_oid} = $functions{$oid};
	}
    }
    %functions = %new_functions;
# }}}

    # {{{ Extend the '%functions' array
    # Add an entry for each pool to the '%functions' array
    # Call 'print_pool_status_info()' for ALL pools - dynamic amount,
    # so we don't need to hardcode them in the initialisation at the top
    my($i, $j) = (0, 2);
    for(; $i < keys(%keys_pools); $i++, $j++) {
	$functions{$OID_BASE.".05.1.$j"} = "pool_status_info";
    }

    # Ditto for the ARC Usage.
    ($i, $j) = (0, 2);
    for(; $i < keys(%keys_arc_usage); $i++, $j++) {
	$functions{$OID_BASE.".06.1.$j"} = "arc_usage_info";
    }

    # ... and ARC Stats.
    ($i, $j) = (0, 2);
    for(; $i < keys(%keys_arc_stats); $i++, $j++) {
	$functions{$OID_BASE.".07.1.$j"} = "arc_stats_info";
    }

    # ... and VFS IOPS Stats.
    ($i, $j) = (0, 2);
    for(; $i < keys(%keys_vfs_iops); $i++, $j++) {
	$functions{$OID_BASE.".08.1.$j"} = "vfs_iops_info";
    }

    # ... and VFS Bandwidth Stats.
    ($i, $j) = (0, 2);
    for(; $i < keys(%keys_vfs_bwidth); $i++, $j++) {
	$functions{$OID_BASE.".09.1.$j"} = "vfs_bandwidth_info";
    }

    # ... and ZIL Stats.
    ($i, $j) = (0, 2);
    for(; $i < keys(%keys_zil_stats); $i++, $j++) {
	$functions{$OID_BASE.".10.1.$j"} = "zil_stats_info";
    }

    # ... and zpool device stats.
    ($i, $j) = (0, 2);
    for(; $i < keys(%keys_dev_stats); $i++, $j++) {
	$functions{$OID_BASE.".11.1.$j"} = "pool_device_status_info";
    }

    # ... and DBUF stats.
    ($i, $j) = (0, 2);
    for(; $i < keys(%keys_dbuf_stats); $i++, $j++) {
	$functions{$OID_BASE.".12.1.$j"} = "dbuf_stats_info";
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
	debug(0, "=> ARG=$arg\n") if($CFG{'DEBUG'} > 2);
	
	# Get next line from STDIN -> OID number.
	# $arg == 'getnext' => Get next OID
	# $arg == 'get'     => Get specified OID
	$oid = <>; chomp($oid);
	$oid =~ s/$OID_BASE//; # Remove the OID base
	$oid =~ s/OID_BASE//;  # Remove the OID base (if we're debugging)
	$oid =~ s/^\.//;       # Remove the first dot if it exists - it's in the way!
	debug(0, "=> OID=$OID_BASE.$oid\n") if($CFG{'DEBUG'} > 2);
	
	my @tmp = split('\.', $oid);
	output_extra_debugging(@tmp) if($CFG{'DEBUG'} > 2);
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
			$tmp[1] = 1;
			if($CFG{'IGNORE_INDEX'}) {
			    $tmp[2] = 2; # Skip 'OID_BASE.5.1.1' => Index!
			} else {
			    $tmp[2] = 1; # Show Index!
			}
			$tmp[3] = 1;

			# How to call call_print()
			my($next1, $next2, $next3) = get_next_oid(@tmp);

			debug(0, ">> Get next OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} >= 2);
			&call_print($next1, $next3);
		    } else {
			&call_print($OID_BASE.".".$tmp[0]);
		    }
		}
# }}} # OID_BASE.[1-4]

	    } elsif(($tmp[0] == 5)  || ($tmp[0] == 8) || ($tmp[0] == 9) ||
		    ($tmp[0] == 11) || ($tmp[0] == 12)) {
		# {{{ ------------------------------------- OID_BASE.{5,8,9,11,12}   
		# {{{ Figure out the NEXT value from the input
		# NOTE: Make sure to skip the OID_BASE.{5,8,9,11,12}.1.1 branch - it's the index and should not be returned!
		if(!defined($tmp[1]) || !defined($tmp[2])) {
		    $tmp[1] = 1;
		    if($CFG{'IGNORE_INDEX'}) {
			# Called only as 'OID_BASE.{5,8,9,11,12}' (jump directly to OID_BASE.{5,8,9,11,12}.1.2 because of the index).
			$tmp[2] = 2;
		    } else {
			$tmp[2] = 1; # Show index.
		    }
		    $tmp[3] = 1;

		} elsif(!defined($tmp[3])) {
		    # Called only as 'OID_BASE.{5,8,9,11,12}.1.x'
		    $tmp[2] = 1 if($tmp[2] == 0);

		    if(($tmp[2] == 1) && $CFG{'IGNORE_INDEX'}) {
			# The index, skip it!
			no_value();
			next;
		    } else {
			$tmp[3] = 1;
		    }
		} else {
		    if((($tmp[0] == 5)  && ($tmp[2] >= keys(%keys_pools)+2))      ||
		       (($tmp[0] == 8)  && ($tmp[2] >= keys(%keys_vfs_iops)+2))   ||
		       (($tmp[0] == 9)  && ($tmp[2] >= keys(%keys_vfs_bwidth)+2)) ||
		       (($tmp[0] == 11) && ($tmp[2] >= keys(%keys_dev_stats)+2)) ||
		       (($tmp[0] == 12) && ($tmp[2] >= keys(%keys_dbuf_stats)+2)))
		    {
			# Max number of columns reached, start with the next entry line
			$tmp[0]++;
			for(my $i=1; $i <= 3; $i++) { $tmp[$i] = 1; }

		    } elsif(((($tmp[0] == 5) || ($tmp[0] == 8) || ($tmp[0] == 9)) && ($tmp[3] >= $POOLS)) ||
			    (($tmp[0] == 11) && ($tmp[3] >= $DEVICES)) ||
			    (($tmp[0] == 12) && ($tmp[3] >= keys(%DBUFS)))) {
			debug(0, "xx: ---------\n");
			# Max number of POOLS/DEVICES/DBUF entries reached.
			if(($tmp[2] == 1) && $CFG{'IGNORE_INDEX'}) {
			    debug(0, "    skipping index\n");
			    # The index, skip it!
			    no_value();
			    next;
			} else {
			    # We've reached the end of the OID_BASE.{5,8,9,11,12}.1.x.y
			    if((($tmp[0] == 8) || ($tmp[0] == 9)) && ($tmp[2] == 1))
			    {
				# Skip the Pool Name column - these two tables augments the 'zfsPoolStatusTable'
				# !! TODO: Need to verify if we should really do this !!

				# -> OID_BASE.{5,8,9,11}.1.x+2.1
				$tmp[2] = 3;
				$tmp[3] = 1;
			    } else {
				# -> OID_BASE.{5,8,9,11,12}.1.x+1.1
				$tmp[2]++;
				$tmp[3] = 1;
			    }

			    if((($tmp[0] == 5)  && ($tmp[2] >= keys(%keys_pools)+2))      ||
			       (($tmp[0] == 8)  && ($tmp[2] >= keys(%keys_vfs_iops)+2))   ||
			       (($tmp[0] == 9)  && ($tmp[2] >= keys(%keys_vfs_bwidth)+2)) ||
			       (($tmp[0] == 11) && ($tmp[2] >= keys(%keys_dev_stats)+2))  ||
			       (($tmp[0] == 12) && ($tmp[2] >= keys(%keys_dbuf_stats)+2)))
			    {
				# That was the end of the OID_BASE.{5,8,9,11,12}.1.x -> OID_BASE.{5,8,9,11,12}+1.1.1.1.1
				$tmp[0]++;
				for(my $i=1; $i <= 3; $i++) { $tmp[$i] = 1; }
			    }
			}

		    } else {
			debug(0, "yy: ---------\n");
			# Get OID_BASE.{5,8,9,11,12}.1.x.y+1
			if(($tmp[2] == 1) && $CFG{'IGNORE_INDEX'}) {
			    # The index, skip it!
			    no_value();
			    next;
			} else {
			    $tmp[3]++;
			}
		    }
		}

		# How to call call_print()
		my($next1, $next2, $next3) = get_next_oid(@tmp);
# }}} # Figure out next value

		# {{{ Call functions, recursively (1)
		debug(0, ">> Get next OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} >= 2);
		if(!&call_print($next1, $next3)) {
		    no_value();
		}
# }}}
# }}} # OID_BASE.5

	    } elsif(($tmp[0] == 6) || ($tmp[0] == 7) || ($tmp[0] == 10)) {
		# {{{ ------------------------------------- OID_BASE.{6-7,10}   
		# {{{ Figure out the NEXT value from the input
		# NOTE: Make sure to skip the OID_BASE.{6-7,10}.1.1 branch - it's the index and should not be returned!
		if(!defined($tmp[1]) || !defined($tmp[2])) {
		    $tmp[1] = 1;
		    if($CFG{'IGNORE_INDEX'}) {
			# Called only as 'OID_BASE.{6-7,10}' (jump directly to OID_BASE.{6-7,10}.1.2 because of the index).
			$tmp[2] = 2;
		    } else {
			$tmp[2] = 1; # Show index.
		    }
		    $tmp[3] = 1;

		} elsif(!defined($tmp[3])) {
		    # Called only as 'OID_BASE.{6-7,10}.1.x'
		    $tmp[2] = 1 if($tmp[2] == 0);

		    if(($tmp[2] == 1) && $CFG{'IGNORE_INDEX'}) {
			# The index, skip it!
			no_value();
			next;
		    } else {
			$tmp[3] = 1;
		    }

		} else {
		    if((($tmp[0] == 6)  && ($tmp[2] > keys(%keys_arc_usage))) ||
		       (($tmp[0] == 7)  && ($tmp[2] > keys(%keys_arc_stats))) ||
		       (($tmp[0] == 10) && ($tmp[2] > keys(%keys_zil_stats))))
		    {
			# We've reached the end of OID_BASE.X -> OID_BASE.X+1.1.1.1
			$tmp[0]++;
			for(my $i=1; $i <= 3; $i++) { $tmp[$i] = 1; }
			
		    } else {
			# Take the next column
			$tmp[2]++;
		    }
		}
# }}}

		# {{{ Call functions, recursively (1)
		# How to call call_print()
		my($next1, $next2, $next3) = get_next_oid(@tmp);

		debug(0, ">> Get next OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} >= 2);
		if(!&call_print($next1, $next3)) {
		    no_value();
		}
# }}}
# }}}

	    } else {
		# {{{ ------------------------------------- Unknown OID      
		debug(0, "Error: No such OID '$OID_BASE' . '$oid'.\n") if($CFG{'DEBUG'});
		debug(0, "\n") if($CFG{'DEBUG'} > 1);
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
		if(!defined($tmp[1])) {
		    $tmp[1] = 1;
		    if($CFG{'IGNORE_INDEX'}) {
			# Called only as 'OID_BASE.5' (jump directly to OID_BASE.5.1.2 because of the index).
			$tmp[2] = 2;
		    } else {
			$tmp[2] = 1; # Show index.
		    }
		    $tmp[3] = 1;
		} elsif(!defined($tmp[3])) {
		    $tmp[3] = 1;
		}

		# How to call call_print()
		($next1, $next2, $next3) = get_next_oid(@tmp);
	    }

	    debug(0, "=> Get this OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} > 2);
	    if(!&call_print($next1, $next3)) {
		no_value();
		next;
	    }
# }}}
	}
    }
# }}}
}
