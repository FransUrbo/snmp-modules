#!/usr/bin/perl -w

# {{{ $Id: package-snmp-stats.pl,v 1.3 2006-02-07 10:14:29 turbo Exp $
# Extract information about packages installed on the system.
#
# Copyright 2005 Turbo Fredriksson <turbo@bayour.com>.
# This software is distributed under GPL v2.
# }}}

# {{{ Config file description and location.
# Require the file "/etc/dpkg/.packagesnmp" with the following
# defines (example values shown here!):
#
# If the location of the config file isn't good enough for you,
# feel free to change that here.
my $CFG_FILE = "/etc/dpkg/.packagesnmp";
#
#   Optional arguments
#	DEBUG=4
#	DEBUG_FILE=/var/log/package-snmp-stats.log
#	IGNORE_INDEX=1
#
#   Required options
#	PKG_MGR=/usr/bin/dpkg
#	PKG_INFO_HEAD_CNT=5
# }}}

# {{{ Include libraries and setup global variables
# Forces a buffer flush after every print
$|=1;

use strict; 
use POSIX qw(strftime);
use BayourCOM_SNMP;

$ENV{PATH} = "/bin:/usr/bin:/usr/sbin";

my $OID_BASE = "OID_BASE"; # When debugging, it's easier to type this than the full OID
if($ENV{'MIBDIRS'}) {
    # ALWAYS override this if we're running through the SNMP daemon!
    $OID_BASE = ".1.3.6.1.4.1.8767.2.5"; # .iso.org.dod.internet.private.enterprises.bayourcom.snmp.packageStats
}

my %PKGS;  # Package information.
my $NO_PACKAGES = 0; # Number of packages

my %functions = (# Package stats
		 "$OID_BASE.1.1.1" => "package_stats_index",

		 # Package info
		 "$OID_BASE.2.1.1" => "package_info_index");

my @DATA_STATS = ('package', 'version', 'description', 'status');
my @DATA_INFO  = ('priority', 'section', 'maintainer',
		  'source', 'depends', 'recommends',
		  'suggests', 'size', 'md5sum');
# }}}

# ====================================================
# =====    R E T R E I V E  F U N C T I O N S    =====

# {{{ Get package information
sub get_package_info {
    my($pkgname) = shift;
    my(%pkgs, $nr, $key);

    open(STAT, "$CFG{'PKG_MGR'} -s $pkgname 2> /dev/null |")
	|| die("Can't get package status for $pkgname, $!\n");

    my $stat_line = <STAT>;
    if(!$stat_line) {
	$pkgs{'package'} = $pkgname;
	$pkgs{'status'} = "!installed";
	
	return(%pkgs);
    }
    
    do {
	chomp($stat_line);
	
	if(($stat_line =~ /^[a-zA-Z]/) and ($stat_line !~ /^Conffiles:/i)) {
	    my ($key, $value) = split(": ", $stat_line);
	    $key = lc($key);
	    
	    if($key eq "status") {
		$value =  $stat_line;
		$value =~ s/.* //;
	    } else {
		$value =  (split(': ', $stat_line))[1];
	    }
	    
	    if($key eq "depends") {
		my @depends = split(', ', $value);
		for(my $i = 0; $depends[$i]; $i++) {
		    $pkgs{$key}{$i} = $depends[$i];
		}
	    } elsif($key eq "maintainer") {
		my @maints = split(' \<', $value);
		
		$pkgs{$key}{'name'} = $maints[0];
		$pkgs{$key}{'email'} = $maints[1];
		$pkgs{$key}{'email'} =~ s/\>$//;
	    } else {
		$pkgs{$key} = $value;
	    }
	}
	
	$stat_line = <STAT>;
    } while(! eof(STAT));

    close(STAT);

    return(%pkgs);
}
# }}}

# {{{ Get all packages and their info
sub get_packages {
    my %pkgs;
    my $pkgs = 1;

    debug(0, "CMD: ".$CFG{'PKG_MGR'}."-l \\*\n") if($CFG{'DEBUG'} >= 4);
    open(PKG, "$CFG{'PKG_MGR'} -l \\* |")
	|| die("Can't get a list of packages, $!\n");

    # Get the header (not interested!)
    for(my $i=0; $i < 5; $i++) {
	my $line = <PKG>;
    }

    while(! eof(PKG)) {
	my $list_line = <PKG>; chomp($list_line);
	
	my @tmp = split(' ', $list_line);
	my $pkgname = $tmp[1];

	my $nr = sprintf("%06d", $pkgs);

	%{$pkgs{$nr}} = &get_package_info($pkgname);
	
	debug(0, "=>   Package: $pkgs{$nr}{'package'} ($pkgs{$nr}{'status'})\n") if($CFG{'DEBUG'} >= 4);

	last if($pkgs >= 50); # FOR DEBUGGING

	$pkgs++;
    }

    close(PKG);

    return($pkgs, %pkgs);
}
# }}}

# ====================================================
# =====       P R I N T  F U N C T I O N S       =====

# {{{ OID_BASE.1.1.1.x		Output basic package information - index
sub print_package_stats_index {
    my $nr         = shift;
    my $package_no = shift;

    my($pkg_no_msg);
    if(defined($package_no)) {
	$pkg_no_msg = ".$package_no";
    } else {
	$pkg_no_msg = "";
    }

    my $success = 0;

    debug(0, "=> OID_BASE.packageStatsTable.packageStatsEntry.packageIndexStats$pkg_no_msg\n") if($CFG{'DEBUG'} > 1);

    if(defined($package_no)) {
	# {{{ Specific package
	$nr = sprintf("%06d", $package_no);
	if(defined($PKGS{$nr}{'package'})) {
	    debug(0, "$OID_BASE.1.1.1.$package_no = $package_no\n") if($CFG{'DEBUG'});

	    debug(1, "$OID_BASE.1.1.1.$package_no\n");
	    debug(1, "integer\n");
	    debug(1, "$package_no\n");

	    $success = 1;
	}
# }}}
    } else {
	# {{{ ALL packages
	foreach my $package_nr (sort keys %PKGS) {
	    $nr = strip_zeros($package_nr);

	    debug(0, "$OID_BASE.1.1.1.$nr = $nr\n") if($CFG{'DEBUG'});

	    debug(1, "$OID_BASE.1.1.1.$nr\n");
	    debug(1, "integer\n");
	    debug(1, "$nr\n");

	    $success = 1;
	}
# }}}
    }

    debug(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return $success;
}
# }}}

# {{{ OID_BASE.1.1.[2-4].x	Output basic package information - name
sub print_package_stats_data {
    my $package_info_type = shift;
    my $package_no = shift;
    my $success = 0;

    if(defined($package_info_type) && defined($package_no)) {
	# {{{ Specific package
	my $type = $DATA_STATS[$package_info_type-2];
	my $nr = sprintf("%06d", $package_no);

	debug(0, "=> OID_BASE.packageStatsTable.packageStatsEntry.$type.$package_no\n") if($CFG{'DEBUG'} > 1);

	if($PKGS{$nr}{$type}) {
	    my $package_data = $PKGS{$nr}{$type};
	    
	    debug(0, "$OID_BASE.1.1.$package_info_type.$package_no = $package_data\n") if($CFG{'DEBUG'});
	    
	    debug(1, "$OID_BASE.1.1.$package_info_type.$package_no\n");
	    debug(1, "string\n");
	    debug(1, "$package_data\n");
	    
	    return 1;
	} else {
	    return 0;
	}

	debug(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
# }}}
    } else {
	# {{{ ALL packages
	my $type_counter = 2;

	foreach my $type (@DATA_STATS) {
	    debug(0, "=> OID_BASE.packageStatsTable.packageStatsEntry.$type\n") if($CFG{'DEBUG'} > 1);

	    foreach my $package_nr (sort keys %PKGS) {
		my $nr = strip_zeros($package_nr);

		if($PKGS{$package_nr}{$type}) {
		    my $package_data;

		    if (ref($PKGS{$package_nr}{$type}) eq "HASH") {
			for my $i (sort keys(%{$PKGS{$package_nr}{$type}})) {
			    $package_data .= $PKGS{$package_nr}{$type}{$i};
			}
		    } else {
			$package_data = $PKGS{$package_nr}{$type};
		    }

		    debug(0, "$OID_BASE.1.1.$type_counter.$nr = $package_data\n") if($CFG{'DEBUG'});

		    debug(1, "$OID_BASE.1.1.$type_counter.$nr\n");
		    debug(1, "string\n");
		    debug(1, "$package_data\n");

		    $success = 1;
		} else {
		    debug(0, "$OID_BASE.1.1.$type_counter.$nr = n/a\n") if($CFG{'DEBUG'});

		    debug(1, "$OID_BASE.1.1.$type_counter.$nr\n");
		    debug(1, "string\n");
		    debug(1, "n/a\n");
		}
	    }

	    $type_counter++;

	    debug(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
	}

	return $success;
# }}}
    }
}
# }}}


# {{{ OID_BASE.2.1.1.x		Output extra package information - index
sub print_package_info_index {
    my $package_no = shift;
    my($success) = 0;
    my($nr);

    debug(0, "=> OID_BASE.packageInfoTable.packageInfoEntry.packageIndexInfo\n") if($CFG{'DEBUG'} > 1);

    if(defined($package_no)) {
	# {{{ Specific package
	$nr = sprintf("%06d", $package_no);
	if(defined($PKGS{$nr}{'Package'})) {
	    debug(0, "$OID_BASE.2.1.1.$package_no = $package_no\n") if($CFG{'DEBUG'});

	    debug(1, "$OID_BASE.2.1.1.$package_no\n");
	    debug(1, "integer\n");
	    debug(1, "$package_no\n");

	    $success = 1;
	}
# }}}
    } else {
	# {{{ ALL packages
	foreach my $package_nr (sort keys %PKGS) {
	    $nr = strip_zeros($package_nr);

	    debug(0, "$OID_BASE.2.1.1.$nr = $nr\n") if($CFG{'DEBUG'});

	    debug(1, "$OID_BASE.2.1.1.$nr\n");
	    debug(1, "integer\n");
	    debug(1, "$nr\n");

	    $success = 1;
	    $package_nr++;
	}
# }}}
    }

    debug(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return $success;
}
# }}}

# {{{ OID_BASE.2.1.[2-10].x	Output extra package information - priority
sub print_package_info_data {
    my $package_info_type = shift;
    my $package_no = shift;

    if(defined($package_no)) {
	# {{{ Specific package
	debug(0, "=> print_package_info_data($package_info_type, $package_no)\n");

	my $type = $DATA_INFO[$package_info_type-2];
	my $nr = sprintf("%06d", $package_no);

	debug(0, "=> OID_BASE.packageInfoTable.packageInfoEntry.$type.$package_no\n") if($CFG{'DEBUG'} > 1);

	debug(0, "=> CHECK: PKG{$nr}{$type}\n") if($CFG{'DEBUG'} >= 4);
	if($PKGS{$nr}{$type}) {
	    my $package_data = $PKGS{$nr}{$type};
	    
	    debug(0, "$OID_BASE.2.1.$package_info_type.$package_no = $package_data\n") if($CFG{'DEBUG'});
	    
	    debug(1, "$OID_BASE.2.1.$package_info_type.$package_no\n");
	    debug(1, "string\n");
	    debug(1, "$package_data\n");
	} elsif($package_no <= $NO_PACKAGES) {
	    debug(0, "$OID_BASE.2.1.$package_info_type.$package_no = n/a\n") if($CFG{'DEBUG'});
	    
	    debug(1, "$OID_BASE.2.1.$package_info_type.$package_no\n");
	    debug(1, "string\n");
	    debug(1, "n/a\n");
	} else {
	    return 0;
	}

	return 1;
	debug(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
# }}}
    } else {
	# {{{ ALL packages
	my $type_counter = 2;
	foreach my $type (@DATA_INFO) {
	    debug(0, "=> OID_BASE.packageInfoTable.packageInfoEntry.$type\n") if($CFG{'DEBUG'} > 1);

	    foreach my $package_nr (sort keys %PKGS) {
		my $nr = strip_zeros($package_nr);

		if($PKGS{$package_nr}{$type}) {
		    my $package_data;

		    if (ref($PKGS{$package_nr}{$type}) eq "HASH") {
			if($type eq 'maintainer') {
			    $package_data = $PKGS{$package_nr}{$type}{'email'};
			} elsif($type eq 'depends') {
			    for my $i (keys(%{$PKGS{$package_nr}{$type}})) {
				$package_data .= $PKGS{$package_nr}{$type}{$i};
				if($PKGS{$package_nr}{$type}{$i+1}) {
				    $package_data .= ", ";
				}
			    }
			}
		    } else {
			$package_data = $PKGS{$package_nr}{$type};
		    }
		    
		    debug(0, "$OID_BASE.2.1.$type_counter.$nr = $package_data\n") if($CFG{'DEBUG'});

		    debug(1, "$OID_BASE.2.1.$type_counter.$nr\n");
		    debug(1, "string\n");
		    debug(1, "$package_data\n");
		} else {
		    debug(0, "$OID_BASE.2.1.$type_counter.$nr = n/a\n") if($CFG{'DEBUG'});

		    debug(1, "$OID_BASE.2.1.$type_counter.$nr\n");
		    debug(1, "string\n");
		    debug(1, "n/a\n");
		}
	    }

	    $type_counter++;

	    debug(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
	}

	return 1;
# }}}
    }
}
# }}}


# ====================================================
# =====        M I S C  F U N C T I O N S        =====

# {{{ Strip zeros
sub strip_zeros {
    my $value = shift;
    my $nr = $value;

    while($nr =~ /^0/) {
	$nr =~ s/^0//;
    }

    return($nr);
}
# }}}

# {{{ Call function with option
sub call_print {
    my $func_nr  = shift;
    my $func_arg = shift;
    my $function;

    # Make sure that the argument variable is initialized
    $func_arg =  '' if(!defined($func_arg));

    debug(0, "=> call_print($func_nr, $func_arg)\n") if($CFG{'DEBUG'} > 3);
    my $func = $functions{$func_nr};
print "=> func='$func' ($func_nr)\n";
    if($func) {
	$function = "print_".$func;
    } else {
	foreach my $oid (sort keys %functions) {
	    # Take the very first match
	    if($oid =~ /^$func_nr/) {
		debug(0, "=> '$oid =~ /^$func_nr/'\n") if($CFG{'DEBUG'} > 2);
		$function = "print_".$functions{$oid};
print "   function='$function'\n";
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

# ====================================================
# =====          P R O C E S S  A R G S          =====

%CFG = get_config($CFG_FILE);
($NO_PACKAGES, %PKGS) = &get_packages();

debug(0, "=> OID_BASE => '$OID_BASE'\n") if($CFG{'DEBUG'});

# {{{ Go through the argument(s) passed to the program
my $ALL = 0;
for(my $i=0; $ARGV[$i]; $i++) {
    if($ARGV[$i] eq '--help' || $ARGV[$i] eq '-h' || $ARGV[$i] eq '?' ) {
	help();
    } elsif($ARGV[$i] eq '--debug' || $ARGV[$i] eq '-d') {
	$CFG{'DEBUG'}++;
    } elsif($ARGV[$i] eq '--all' || $ARGV[$i] eq '-a') {
	$ALL = 1;
    }
}
# }}}

if($ALL) {
    # {{{ Output the whole MIB tree - used mainly/only for debugging purposes.
    $functions{$OID_BASE.".1.1.2"} = "package_stats_data";
    $functions{$OID_BASE.".2.1.2"} = "package_info_data";

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
    $OID_BASE = ".1.3.6.1.4.1.8767.2.5";

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

    foreach my $oid (sort keys %functions) {
	print "=> functions{$oid} = '$functions{$oid}'\n";
    }

    # {{{ Go through the commands sent on STDIN
    my($arg, $oid, @tmp);

    while(<>) {
	if(m!^PING!) {
	    print "PONG\n";
	    next;
	}

	# Re-get the DEBUG config option (so that we don't have to restart process).
	$CFG{'DEBUG'} = get_config($CFG_FILE, 'DEBUG');

	# {{{ Get all run arguments - next/specfic OID
	# $arg == 'getnext' => Get next OID
	# $arg == 'get'     => Get specified OID
	# $arg == 'set'     => Set value for OID
	my $arg = $_; chomp($arg);

	# Get next line from STDIN -> OID number.
	$oid = <>; chomp($oid);
	$oid =~ s/$OID_BASE//; # Remove the OID base
	$oid =~ s/OID_BASE//;  # Remove the OID base (if we're debugging)
	$oid =~ s/^\.//;       # Remove the first dot if it exists - it's in the way!
	debug(0, "=> OID=$OID_BASE.$oid\n") if($CFG{'DEBUG'} > 2);

	if($CFG{'DEBUG'} >= 2) {
	    my $tmp = $OID_BASE;
	    $tmp .= ".".$oid if($oid);
	    debug(0, "=> ARG='$arg $tmp'\n");
	}
	
	my @tmp = split('\.', $oid);
	output_extra_debugging(@tmp) if($CFG{'DEBUG'} > 2);
# }}}

	if($arg eq 'getnext') {
	    # {{{ Get next OID
	    if(!defined($tmp[0])) {
		# {{{ ------------------------------------- OID_BASE      
		if($CFG{'IGNORE_INDEX'}) {
		    # Skip the index and go directly to DATA_STATS[0] (Package name)
		    &call_print("$OID_BASE.1.1", "2", "1");
		} else {
		    # Print the index
		    &call_print("$OID_BASE.1.1", "1", "1");
		}
# }}} # OID_BASE

	    } elsif(($tmp[0] == 1) || ($tmp[0] == 2)) {
		# {{{ ------------------------------------- OID_BASE.[12] 
		# {{{ Figure out the NEXT value from the input
		if(!defined($tmp[1])) {
		    $tmp[1] = 1;
		} elsif(!defined($tmp[2])) {
		    $tmp[2] = 1;
		} elsif(!defined($tmp[3])) {
		    $tmp[3] = 1;
		} else {
		    $tmp[3]++;
		}
# }}}

		if(($tmp[0] == 1) && ($tmp[2] > $#DATA_STATS+2)) {
		    no_value();
		    next;
		}

		# {{{ Call functions, recursively (1)
		my $new = $OID_BASE.".".$tmp[0].".".$tmp[1];
		debug(0, ">> Get next OID( 1): $new.".$tmp[2].".".$tmp[3]."\n")
		    if($CFG{'DEBUG'} >= 2);
		if(!&call_print($new, $tmp[2], $tmp[3])) {
		    # End of OID_BASE.1.1.x => goto OID_BASE.1.1.x+1.1
		    my $max;
		    if($tmp[0] == 1) {
			$max = $#DATA_STATS+1;
		    } elsif($tmp[0] == 2) {
			$max = $#DATA_INFO+1;
		    }

		    if($tmp[2] <= $max) {
			$tmp[2]++;
			$tmp[3] = 1;
			
			# {{{ Call functions, recursively (-1)
			my $new = $OID_BASE.".".$tmp[0].".".$tmp[1];
			debug(0, ">> Get next OID(-1): $new.".$tmp[2].".".$tmp[3]."\n") if($CFG{'DEBUG'} >= 2);
			if(!&call_print($new, $tmp[2], $tmp[3])) {
			    no_value();
			}
# }}}
		    } elsif($tmp[0] == 1) {
			# {{{ End of OID_BASE.1 => goto OID_BASE.2.1.1.[12].1 (depending of IGNORE_INDEX)
			debug(0, ">> Get next OID(-2): $OID_BASE.2.1.2.1\n") if($CFG{'DEBUG'} >= 2);
			if($CFG{'IGNORE_INDEX'}) {
			    # Skip the index and go directly to DATA_STATS[0] (Package name)
			    &call_print("$OID_BASE.2.1", "2", "1");
			} else {
			    # Print the index
			    &call_print("$OID_BASE.2.1", "1", "1");
			}
# }}}
		    } else {
			no_value();
		    }
		}
# }}} # Call functions ->  1
# }}}

	    }
# }}}

	} elsif($arg eq 'get') {
	    # {{{ Get _this_ OID
	    if(($tmp[1] == 1) && ($tmp[2] > $#DATA_STATS+2)) {
		no_value();
		next;
	    }

	    my $new = $OID_BASE.".".$tmp[0].".".$tmp[1];
	    debug(0, ">> Get this OID( 1): $new.".$tmp[2].".".$tmp[3]."\n") if($CFG{'DEBUG'} >= 2);
	    if(!&call_print($new, $tmp[2], $tmp[3])) {
		no_value();
		next;
	    }
# }}}
	}

	debug(0, "\n") if($CFG{'DEBUG'} > 1);
    }
# }}}
}
