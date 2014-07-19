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

# {{{ The 'flow' of the OID/MIB tree.
my %functions  = ($OID_BASE.".01"	=> "amount_pools",
		  $OID_BASE.".02"	=> "amount_datasets",
		  $OID_BASE.".03"	=> "amount_volumes",
		  $OID_BASE.".04"	=> "amount_snapshots",

		  $OID_BASE.".05.1.1"	=> "pool_status_index",
		  $OID_BASE.".05.1.2"	=> "pool_status_info");

my %keys_pools = (#01  => index
		  "02" => "name",
		  "03" => "size",
		  "04" => "alloc",
		  "05" => "free",
		  "06" => "cap",
		  "07" => "dedup",
		  "08" => "health",
		  "09" => "altroot");
# }}}

# {{{ Pool status values
my %pool_status = ('DEGRADED'	=> 1,
		   'FAULTED'	=> 2,
		   'OFFLINE'	=> 3,
		   'ONLINE'	=> 4,
		   'REMOVED'	=> 5,
		   'UNAVAIL'	=> 6);
# }}}

# {{{ Some global data variables
my(%POOLS, %DATASETS, %SNAPSHOTS, %VOLUMES);
my($POOLS, $DATASETS, $SNAPSHOTS, $VOLUMES);
my($oid, $arg, $TYPE_STATUS);
# }}}

# handle a SIGALRM - reload information/statistics and
# config file.
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

# {{{ Get all pools and their data
sub get_pools {
    my(%POOLS);
    my $pools = 0;

    open(ZPOOL, "$CFG{'ZPOOL'} list -H |") ||
	die("Can't call $CFG{'ZPOOL'}, $!");
    while(! eof(ZPOOL)) {
	my $pool = <ZPOOL>;
	chomp($pool);

	return(0, ()) if($pool eq 'no pools available');
	my $pool_name = (split(' ', $pool))[0];

	($POOLS{$pool_name}{'name'}, $POOLS{$pool_name}{'size'},
	 $POOLS{$pool_name}{'alloc'}, $POOLS{$pool_name}{'free'},
	 $POOLS{$pool_name}{'cap'}, $POOLS{$pool_name}{'dedup'},
	 $POOLS{$pool_name}{'health'}, $POOLS{$pool_name}{'altroot'})
	    = split(' ', $pool);

	$pools++;
    }
    close(ZPOOL);

    my @keys = ("size", "alloc", "free");
    foreach my $pool_name (keys %POOLS) {
	for(my $i = 0; $i <= $#keys; $i++) {
	    my $key = $keys[$i];
	    
	    $POOLS{$pool_name}{$key} = &size_to_human($POOLS{$pool_name}{$key});
	}

	chop($POOLS{$pool_name}{'cap'});
	chop($POOLS{$pool_name}{'dedup'});
    }

    return($pools, %POOLS);
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

    return($i, %LIST);
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
    my $pool_no = shift; # Pool number
    my $success = 0;
    debug(0, "=> OID_BASE.zfsPoolStatusTable.zfsPoolStatusEntry.zfsPoolStatusIndex\n") if($CFG{'DEBUG'} > 1);

    if(defined($pool_no)) {
	# {{{ Specific pool name
	foreach my $key_nr (sort keys %keys_pools) {
	    my $value = sprintf("%02d", $TYPE_STATUS+1); # This is the index - offset one!
	    if($key_nr == $value) {
		my $key_name = $keys_pools{$key_nr};
		$key_nr =~ s/^0//;
		$key_nr -= 1; # This is the index - offset one!
		debug(0, "=> OID_BASE.zfsPoolStatusTable.zfsPoolStatusEntry.$key_name.zfsPoolName\n") if($CFG{'DEBUG'} > 1);
		
		my $pool_nr = 1;
		foreach my $pool_name (sort keys %POOLS) {
		    if($pool_nr == $pool_no) {
			debug(0, "$OID_BASE.5.1.$key_nr.$pool_nr = $pool_nr\n") if($CFG{'DEBUG'});
			
			debug(1, "$OID_BASE.5.1.$key_nr.$pool_nr\n");
			debug(1, "integer\n");
			debug(1, "$pool_nr\n");
			
			$success = 1;
		    }

		    $pool_nr++;
		}
	    }
	}
# }}}
    } else {
	# {{{ ALL pool values
	my $pool_nr = 1;
	foreach my $pool_name (sort keys %POOLS) {
	    debug(0, "$OID_BASE.5.1.1.$pool_nr = $pool_nr\n") if($CFG{'DEBUG'});
	    
	    debug(1, "$OID_BASE.5.1.1.$pool_nr\n");
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

# {{{ OID_BASE.5.1.X.x          Output pool status information
sub print_pool_status_info {
    my $value_no = shift; # Value number
    my $success = 0;

    if(defined($value_no)) {
	# {{{ Specific client name
	foreach my $key_nr (sort keys %keys_pools) {
	    my $value = sprintf("%02d", $TYPE_STATUS);
	    if($key_nr == $value) {
		my $key_name = $keys_pools{$key_nr};
		$key_nr =~ s/^0//;
		debug(0, "=> OID_BASE.zfsPoolStatusTable.zfsPoolStatusEntry.$key_name.zfsPoolName\n") if($CFG{'DEBUG'} > 1);
		
		my $pool_nr = 1;
		foreach my $pool_name (sort keys %POOLS) {
		    if($pool_nr == $value_no) {
			debug(0, "$OID_BASE.5.1.$key_nr.$pool_nr = ".$POOLS{$pool_name}{$key_name}."\n") if($CFG{'DEBUG'});
			
			debug(1, "$OID_BASE.5.1.$key_nr.$pool_nr\n");
			if(($key_name eq 'altroot') ||
			   ($key_name eq 'name')    ||
			   ($key_name eq 'dedup'))
			{
			    debug(1, "string\n");
			} else {
			    debug(1, "integer\n");
			}

			if($key_name eq 'health') {
			    my $stat = $POOLS{$pool_name}{$key_name};
			    debug(1, $pool_status{$stat}."\n");
			} else {
			    debug(1, $POOLS{$pool_name}{$key_name}."\n");
			}
			
			$success = 1;
		    }

		    $pool_nr++;
		}
	    }
	}
# }}}
    } else {
	# {{{ ALL pools
	foreach my $key_nr (sort keys %keys_pools) {
	    my $key_name = $keys_pools{$key_nr};
	    $key_nr =~ s/^0//;
	    debug(0, "=> OID_BASE.zfsPoolStatusTable.zfsPoolStatusEntry.$key_name.zfsPoolName\n") if($CFG{'DEBUG'} > 1);
	    
	    my $pool_nr = 1;
	    foreach my $pool_name (sort keys %POOLS) {
		debug(0, "$OID_BASE.5.1.$key_nr.$pool_nr = ".$POOLS{$pool_name}{$key_name}."\n") if($CFG{'DEBUG'});
		
		debug(1, "$OID_BASE.5.1.$key_nr.$pool_nr\n");
		if(($key_name eq 'altroot') ||
		    ($key_name eq 'name')   ||
		    ($key_name eq 'dedup'))
		{
		    debug(1, "string\n");
		} else {
		    debug(1, "integer\n");
		}

		if($key_name eq 'health') {
		    my $stat = $POOLS{$pool_name}{$key_name};
		    debug(1, $pool_status{$stat}."\n");
		} else {
		    debug(1, $POOLS{$pool_name}{$key_name}."\n");
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
#    alarm(60*60);
}
# }}}

# {{{ Convert human readable size to raw bytes
sub size_to_human {
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
    if($tmp[0] == 5) {
	# {{{ ------------------------------------- OID_BASE.5       
	$TYPE_STATUS = $tmp[2];
# }}} # OID_BASE.5
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

if($ALL) {
    # Load information
    &load_information();

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
    # so we can't hardcode them in the initialisation at the top
    my($i, $j) = (0, 3);
    for(; $i < keys(%keys_pools)-1; $i++, $j++) {
	$functions{$OID_BASE.".05.1.$j"} = "pool_status_info";
    }
# }}}

    # {{{ Go through the commands sent on STDIN
    while(<>) {
	if (m!^PING!){
	    print "PONG\n";
	    next;
	}

	# Load information - make sure we get latest info available
	&load_information();
	
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

	    } elsif( $tmp[0] == 5) {
		# {{{ ------------------------------------- OID_BASE.5       
		# {{{ Figure out the NEXT value from the input
		# NOTE: Make sure to skip the OID_BASE.5.1.1 branch - it's the index and should not be returned!
		if(!defined($tmp[1]) || !defined($tmp[2])) {
		    $tmp[1] = 1;
		    if($CFG{'IGNORE_INDEX'}) {
			# Called only as 'OID_BASE.5' (jump directly to OID_BASE.5.1.2 because of the index).
			$tmp[2] = 2;
		    } else {
			$tmp[2] = 1; # Show index.
		    }
		    $tmp[3] = 1;

		} elsif(!defined($tmp[3])) {
		    # Called only as 'OID_BASE.5.1.x'
		    $tmp[2] = 1 if($tmp[2] == 0);

		    if(($tmp[2] == 1) && $CFG{'IGNORE_INDEX'}) {
			# The index, skip it!
			no_value();
			next;
		    } else {
			$tmp[3] = 1;
		    }

		} else {
		    if($tmp[2] >= keys(%keys_pools)+2) {
			# We've reached the ned of the OID_BASE.5.1.x -> OID_BASE.6.1.1.1.1
#			$tmp[0]++;
#			for(my $i=1; $i <= 3; $i++) { $tmp[$i] = 1; }
			no_value();

		    } elsif($tmp[3] >= $POOLS) {
			if(($tmp[2] == 1) && $CFG{'IGNORE_INDEX'}) {
			    # The index, skip it!
			    no_value();
			    next;
			} else {
			    # We've reached the end of the OID_BASE.5.1.x.y -> OID_BASE.5.1.x+1.1
			    $tmp[2]++;
			    $tmp[3] = 1;
			}

		    } else {
			# Get OID_BASE.5.1.x.y+1
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

#		    # OID_BASE.5.1.2.4 => OID_BASE.5.1.3.1
#		    # {{{ Figure out the NEXT value from the input
#		    $tmp[0]++;   # Go to OID_BASE.6
#		    $tmp[1] = 1;
#		    if($CFG{'IGNORE_INDEX'}) {
#			$tmp[2] = 2; # Skip 'OID_BASE.6.1.1' => Index!
#		    } else {
#			$tmp[2] = 1; # Show Index!
#		    }
#		    $tmp[3] = 1;
#
#		    # How to call call_print()
#		    my($next1, $next2, $next3) = get_next_oid(@tmp);
## }}} # Figure out next value
#
#		    debug(0, ">> No OID at that level (-1) - get next branch OID: $next1$next2.$next3\n") if($CFG{'DEBUG'} >= 2);
#		    &call_print($next1, $next3);
		}
# }}}
# }}} # OID_BASE.5

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
