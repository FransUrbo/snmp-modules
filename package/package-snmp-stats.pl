#!/usr/bin/perl -w

# {{{ $Id: package-snmp-stats.pl,v 1.1 2006-02-05 11:51:08 turbo Exp $
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
#	DEBUG_FILE=/var/log/bind9-snmp-stats.log
#	IGNORE_INDEX=1
#
#   Required options
#	PKG_MGR=/usr/bin/dpkg
#	PKG_INFO=-l
#	PKG_STAT=-s
# }}}

# {{{ Include libraries and setup global variables
# Forces a buffer flush after every print
$|=1;

use strict; 
use POSIX qw(strftime);
use BayourCOM_SNMP;

$ENV{PATH} = "/bin:/usr/bin:/usr/sbin";
my %CFG;

my $OID_BASE;
$OID_BASE = "OID_BASE"; # When debugging, it's easier to type this than the full OID
if($ENV{'MIBDIRS'}) {
    # ALWAYS override this if we're running through the SNMP daemon!
    $OID_BASE = ".1.3.6.1.4.1.8767.2.5"; # .iso.org.dod.internet.private.enterprises.bayourcom.snmp.packageStats
}
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


# ====================================================
# =====       P R I N T  F U N C T I O N S       =====


# ====================================================
# =====        M I S C  F U N C T I O N S        =====


# ====================================================
# =====          P R O C E S S  A R G S          =====

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
