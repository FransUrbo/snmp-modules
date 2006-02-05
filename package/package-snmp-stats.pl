#!/usr/bin/perl -w

# {{{ $Id: package-snmp-stats.pl,v 1.2 2006-02-05 18:48:52 turbo Exp $
# Extract information about packages installed on the system.
#
# Copyright 2005 Turbo Fredriksson <turbo@bayour.com>.
# This software is distributed under GPL v2.
# }}}

# {{{ Config file description and location.
# Require the file "/etc/bind/.bindsnmp" with the following
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
#	PKG_INFO="-l \*"
#	PKG_STAT=-s
#	PKG_INFO_HEAD_CNT=5
# }}}

# {{{ Include libraries and setup global variables
# Forces a buffer flush after every print
$|=1;

use strict; 
use POSIX qw(strftime);
use BayourCOM_SNMP;

$ENV{PATH} = "/bin:/usr/bin:/usr/sbin";
our %CFG;

my $OID_BASE;
$OID_BASE = "OID_BASE"; # When debugging, it's easier to type this than the full OID
if($ENV{'MIBDIRS'}) {
    # ALWAYS override this if we're running through the SNMP daemon!
    $OID_BASE = ".1.3.6.1.4.1.8767.2.5"; # .iso.org.dod.internet.private.enterprises.bayourcom.snmp.packageStats
}

my %PKG;  # Package information.

my %functions = (# Package stats
		 "$OID_BASE.1.1.1" => "package_stats_index",
		 "$OID_BASE.1.1.2" => "package_stats_data",	# name

		 # Package info
		 "$OID_BASE.2.1.1" => "package_info_index",
		 "$OID_BASE.2.1.2" => "package_info_data");	# prio

my @DATA_STATS = ('Package', 'Version', , 'Description');
my @DATA_INFO  = ('Priority', 'Section', 'Maintainer',
		  'Source', 'Depends', 'Recommends',
		  'Suggests', 'Size', 'MD5sum');
# }}}

# {{{ OID tree
# smidump -f tree BAYOUR-COM-MIB.txt
# +--packageStats(5)
#    |
#    +--packageStatsTable(1)
#    |  |
#    |  +--packageStatsEntry(1) [packageIndexStats]
#    |     |
#    |     +-- --- CounterIndex  packageIndexStats(1)
#    |     +-- r-n DisplayString packageName(2)
#    |     +-- r-n DisplayString packageVersion(3)
#    |     +-- r-n DisplayString packageDesc(4)
#    |     +-- r-n DisplayString packageStatus(5)
#    |
#    +--packageInfoTable(2)
#       |
#       +--packageInfoEntry(1) [packageIndexInfo]
#          |
#          +-- --- CounterIndex  packageIndexInfo(1)
#          +-- r-n DisplayString packagePriority(2)
#          +-- r-n DisplayString packageSection(3)
#          +-- r-n DisplayString packageMaintainer(4)
#          +-- r-n DisplayString packageSource(5)
#          +-- r-n DisplayString packageDepends(6)
#          +-- r-n DisplayString packageRecommends(7)
# }}}

# ====================================================
# =====    R E T R E I V E  F U N C T I O N S    =====

# {{{ Get all packages and their info
sub get_packages {
    my($i, $line, $nr);
    my($pkg_count) = 0;

    &echo(0, "CMD: '".$CFG{'PKG_LIST'}."'\n") if($CFG{'DEBUG'} >= 4);
    if($CFG{'PKG_LIST'} =~ /\ /) {
	open(PKG, "$CFG{'PKG_LIST'} |")
	    || die("Can't get a list of packages, $!\n");
    } else {
	open(PKG, $CFG{'PKG_LIST'})
	    || die("Can't get a list of packages, $!\n");
    }

    while(! eof(PKG)) {
	$line = <PKG>; chomp($line);

	if(($line =~ /^[a-zA-Z]/) && ($line !~ /^Conffiles:/i)) {
	    my ($key, $value) = split(": ", $line);
	    $key =~ s/: //;

	    if($key eq "Package") {
		$pkg_count++;
		$nr = sprintf("%06d", $pkg_count);
		&echo(0, "=> $nr:\n") if($CFG{'DEBUG'} >= 4);
	    }

	    &echo(0, "=>   $key: $value\n") if($CFG{'DEBUG'} >= 4);
	    $PKG{$nr}{$key} = $value;
	}
    }

    close(PKG);
}
# }}}

# ====================================================
# =====       P R I N T  F U N C T I O N S       =====

# {{{ OID_BASE.1.1.1.x		Output basic package information - index
sub print_package_stats_index {
    my $package_no = shift;
    my $success = 0;
    my $nr;

    &echo(0, "=> OID_BASE.packageStatsTable.packageStatsEntry.packageIndexStats\n") if($CFG{'DEBUG'} > 1);

    if(defined($package_no)) {
	# {{{ Specific package
# }}}
    } else {
	# {{{ ALL packages
	foreach my $package_nr (sort keys %PKG) {
	    $nr = strip_zeros($package_nr);

	    &echo(0, "$OID_BASE.1.1.1.$nr = $nr\n") if($CFG{'DEBUG'});

	    &echo(1, "$OID_BASE.1.1.1.$nr\n");
	    &echo(1, "integer\n");
	    &echo(1, "$nr\n");

	    $success = 1;
	}
# }}}
    }

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return $success;
}
# }}}

# {{{ OID_BASE.1.1.[2-4].x	Output basic package information - name
sub print_package_stats_data {
    my $package_no = shift;
    my $package_info_type = shift;
    my $success = 0;

    if(defined($package_no)) {
	# {{{ Specific package
# }}}
    } else {
	# {{{ ALL packages
	my $type_counter = 2;
	foreach my $type (@DATA_STATS) {
	    &echo(0, "=> OID_BASE.packageStatsTable.packageStatsEntry.$type\n") if($CFG{'DEBUG'} > 1);

	    foreach my $package_nr (sort keys %PKG) {
		my $nr = strip_zeros($package_nr);

		if($PKG{$package_nr}{$type}) {
		    my $package_data = $PKG{$package_nr}{$type};
		    
		    &echo(0, "$OID_BASE.1.1.$type_counter.$nr = $package_data\n") if($CFG{'DEBUG'});

		    &echo(1, "$OID_BASE.1.1.$type_counter.$nr\n");
		    &echo(1, "string\n");
		    &echo(1, "$package_data\n");

		    $success = 1;
		} else {
		    &echo(0, "$OID_BASE.1.1.$type_counter.$nr = n/a\n") if($CFG{'DEBUG'});

		    &echo(1, "$OID_BASE.1.1.$type_counter.$nr\n");
		    &echo(1, "string\n");
		    &echo(1, "n/a\n");
		}
	    }

	    $type_counter++;

	    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
	}
# }}}
    }

    return $success;
}
# }}}


# {{{ OID_BASE.2.1.1.x		Output extra package information - index
sub print_package_info_index {
    my $package_no = shift;
    my($success) = 0;
    my($nr);

    &echo(0, "=> OID_BASE.packageInfoTable.packageInfoEntry.packageIndexInfo\n") if($CFG{'DEBUG'} > 1);

    if(defined($package_no)) {
	# {{{ Specific package
# }}}
    } else {
	# {{{ ALL packages
	foreach my $package_nr (sort keys %PKG) {
	    $nr = strip_zeros($package_nr);

	    &echo(0, "$OID_BASE.2.1.1.$nr = $nr\n") if($CFG{'DEBUG'});

	    &echo(1, "$OID_BASE.2.1.1.$nr\n");
	    &echo(1, "integer\n");
	    &echo(1, "$nr\n");

	    $success = 1;
	    $package_nr++;
	}
# }}}
    }

    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
    return $success;
}
# }}}

# {{{ OID_BASE.2.1.[2-10].x	Output extra package information - priority
sub print_package_info_data {
    my $package_no = shift;
    my $package_info_type = shift;
    my $success = 0;

    if(defined($package_no)) {
	# {{{ Specific package
# }}}
    } else {
	# {{{ ALL packages
	my $type_counter = 2;
	foreach my $type (@DATA_INFO) {
	    &echo(0, "=> OID_BASE.packageInfoTable.packageInfoEntry.$type\n") if($CFG{'DEBUG'} > 1);

	    foreach my $package_nr (sort keys %PKG) {
		my $nr = strip_zeros($package_nr);

		if($PKG{$package_nr}{$type}) {
		    my $package_data = $PKG{$package_nr}{$type};
		    
		    &echo(0, "$OID_BASE.1.1.$type_counter.$nr = $package_data\n") if($CFG{'DEBUG'});

		    &echo(1, "$OID_BASE.1.1.$type_counter.$nr\n");
		    &echo(1, "string\n");
		    &echo(1, "$package_data\n");

		    $success = 1;
		} else {
		    &echo(0, "$OID_BASE.1.1.$type_counter.$nr = n/a\n") if($CFG{'DEBUG'});

		    &echo(1, "$OID_BASE.1.1.$type_counter.$nr\n");
		    &echo(1, "string\n");
		    &echo(1, "n/a\n");
		}
	    }

	    $type_counter++;

	    &echo(0, "\n") if(($CFG{'DEBUG'} > 2) && !$ENV{'MIBDIRS'});
	}
# }}}
    }

    return $success;
}
# }}}


# ====================================================
# =====        M I S C  F U N C T I O N S        =====

# {{{ Log output wrapper
sub echo {
    my $stdout = shift;
    my $string = shift;

    BayourCOM_SNMP::echo($stdout, $string);
}
# }}}

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

# ====================================================
# =====          P R O C E S S  A R G S          =====

%CFG = BayourCOM_SNMP::get_config($CFG_FILE);
&get_packages();

BayourCOM_SNMP::echo(0, "=> OID_BASE => '$OID_BASE'\n") if($CFG{'DEBUG'});

# {{{ Go through the argument(s) passed to the program
my $ALL = 0;
for(my $i=0; $ARGV[$i]; $i++) {
    if($ARGV[$i] eq '--help' || $ARGV[$i] eq '-h' || $ARGV[$i] eq '?' ) {
	BayourCOM_SNMP::help();
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
    # {{{ Go through the commands sent on STDIN
    my($arg, $oid, @tmp);

    while(<>) {
	if (m!^PING!){
	    print "PONG\n";
	    next;
	}

	# Re-get the DEBUG config option (so that we don't have to restart process).
	%CFG = BayourCOM_SNMP::get_config($CFG_FILE, 'DEBUG');

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

	BayourCOM_SNMP::echo(0, "=> ARG='$arg  $OID_BASE.$oid'\n") if($CFG{'DEBUG'} >= 2);
	
	my @tmp = split('\.', $oid);
	BayourCOM_SNMP::output_extra_debugging(@tmp) if($CFG{'DEBUG'} > 2);
# }}}

	if($arg eq 'getnext') {
	    # {{{ Get next OID
# }}}
	} elsif($arg eq 'get') {
	    # {{{ Get _this_ OID
# }}}
	}

	BayourCOM_SNMP::echo(0, "\n") if($CFG{'DEBUG'} > 1);
    }
# }}}
}
