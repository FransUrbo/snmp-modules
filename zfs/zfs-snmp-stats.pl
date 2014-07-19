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
my $arg      = '';

# {{{ The 'flow' of the OID/MIB tree.
my %functions  = ($OID_BASE.".01"	=> "amount_pools",
		  $OID_BASE.".02"	=> "amount_datasets",
		  $OID_BASE.".03"	=> "amount_volumes",
		  $OID_BASE.".04"	=> "amount_snapshots");
# }}}

my $POOLS;
my %POOLS	= ( );

my $DATASETS;
my %DATASETS	= ( );

my $SNAPSHOTS;
my %SNAPSHOTS	= ( );

my $VOLUMES;
my %VOLUMES	= ( );

# The input OID
my($oid);

# handle a SIGALRM - read statistics file
$SIG{'ALRM'} = \&load_information;
# }}}

# ====================================================
# =====    R E T R E I V E  F U N C T I O N S    =====

# {{{ ZFS Get Property
sub zfs_get_prop {
    my($prop, $fs);

    system("$CFG{'ZFS'} get -H -ovalue $prop $fs");
}
# }}}

# {{{ ZPOOL Get Property
sub zpool_get_prop {
    my $prop = shift;
    my $pool = shift;

    my $val = (split(' ', `$CFG{'ZPOOL'} get $prop $pool | egrep ^$pool"`))[3];
    print $val;
}
# }}}

# {{{ Get all pools
sub get_pools {
    my(%POOLS);
    my $i = 0;

    open(ZPOOL, "$CFG{'ZPOOL'} list -H |") ||
	die("Can't call $CFG{'ZPOOL'}, $!");
    while(! eof(ZPOOL)) {
	my $pool = <ZPOOL>;
	chomp($pool);

	return(0, ()) if($pool eq 'no pools available');

	($POOLS{'name'}, $POOLS{'size'}, $POOLS{'alloc'},
	 $POOLS{'free'}, $POOLS{'cap'}, $POOLS{'dedup'},
	 $POOLS{'health'}, $POOLS{'altroot'}) = split(' ', $pool);

	$i++;
    }
    close(ZPOOL);

    return($i, %POOLS);
}
# }}}

# {{{ Get all filesystems/volumes/snapshots
sub get_list {
    my $type = shift;
    my(%LIST);
    my $i = 0;

    open(ZFS, "$CFG{'ZFS'} list -H -t$type |") ||
	die("Can't call $CFG{'ZFS'}, $!");
    while(! eof(ZFS)) {
	my $fs = <ZFS>;
	chomp($fs);

	return(0, ()) if($fs eq 'no datasets available');

	($LIST{'name'}, $LIST{'used'}, $LIST{'avail'},
	 $LIST{'refer'}, $LIST{'mountpoint'}) = split(' ', $fs);

	$i++;
    }
    close(ZFS);

    return($i, %DATASETS);
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

# {{{ OID_BASE.4.0              output total number of snapshots
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
    # Load configuration file and connect to SQL server.
    %CFG = get_config($CFG_FILE);

    # Get pools, filesystems, snapshots and volumes
    ($POOLS,     %POOLS)     = &get_pools();
    ($DATASETS,  %DATASETS)  = &get_list('filesystem');
    ($VOLUMES,   %VOLUMES)   = &get_list('volume');
    ($SNAPSHOTS, %SNAPSHOTS) = &get_list('snapshot');

    # Schedule an alarm once every hour to re-read information.
    alarm(60*60);
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

# Load information
&load_information();

if($ALL) {
    # {{{ Output the whole MIB tree - used mainly/only for debugging purposes
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

    # {{{ Rewrite the functions array
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

    # {{{ Go through the commands sent on STDIN
    while(<>) {
	if (m!^PING!){
	    print "PONG\n";
	    next;
	}

	# Re-get the DEBUG config option (so that we don't have to restart process).
	$CFG{'DEBUG'} = get_config($CFG_FILE, 'DEBUG');
	
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
