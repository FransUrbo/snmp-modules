#!/usr/bin/perl -w

# {{{ $Id: system-snmp-stats.pl,v 1.1 2006-02-05 11:55:44 turbo Exp $
# Extract information and statistics about the system.
#
# Copyright 2005 Turbo Fredriksson <turbo@bayour.com>.
# This software is distributed under GPL v2.
# }}}

# {{{ Config file description and location.
# Require the file "/etc/snmp/.systemsnmp" with the following
# defines (example values shown here!):
#
# If the location of the config file isn't good enough for you,
# feel free to change that here.
my $CFG_FILE = "/etc/snmp/.systemsnmp";
#
#   Optional arguments
#	DEBUG=4
#	DEBUG_FILE=/var/log/system-snmp-stats.log
#	IGNORE_INDEX=1
#
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
    $OID_BASE = ".1.3.6.1.4.1.8767.2.4"; # .iso.org.dod.internet.private.enterprises.bayourcom.snmp.systemStats
}
# }}}

# {{{ OID tree
# smidump -f tree BAYOUR-COM-MIB.txt
# +--systemStats(4)
#    |
#    +-- r-n Integer32 systemUptime(1)
#    |
#    +--systemMemoryTable(2)
#    |  |
#    |  +--systemMemoryEntry(1) [systemMemoryIndex]
#    |     |
#    |     +-- --- CounterIndex systemMemoryIndex(1)
#    |     +-- r-n Integer32    systemMemoryTotal(2)
#    |     +-- r-n Integer32    systemMemoryUsed(3)
#    |     +-- r-n Integer32    systemMemoryBuffered(4)
#    |     +-- r-n Integer32    systemMemoryCached(5)
#    |     +-- r-n Integer32    systemMemorySwapTotal(6)
#    |     +-- r-n Integer32    systemMemorySwapUsed(7)
#    |
#    +--systemCPUTable(3)
#    |  |
#    |  +--systemCPUEntry(1) [systemCPUIndex]
#    |     |
#    |     +-- --- CounterIndex systemCPUIndex(1)
#    |     +-- r-n Integer32    systemCPUTasksTotal(2)
#    |     +-- r-n Integer32    systemCPUTasksRunning(3)
#    |     +-- r-n Integer32    systemCPUTasksSleeping(4)
#    |     +-- r-n Integer32    systemCPUTasksStopped(5)
#    |     +-- r-n Integer32    systemCPUTasksZombies(6)
#    |     +-- r-n Integer32    systemCPUUsageUser(7)
#    |     +-- r-n Integer32    systemCPUUsageSystem(8)
#    |     +-- r-n Integer32    systemCPUUsageNice(9)
#    |     +-- r-n Integer32    systemCPUUsageIdle(10)
#    |     +-- r-n Integer32    systemCPUUsageIOWait(11)
#    |
#    +--systemLoadTable(4)
#       |
#       +--systemLoadEntry(1) [systemLoadIndex]
#          |
#          +-- --- CounterIndex systemLoadIndex(1)
#          +-- r-n Integer32    systemLoadLastOne(2)
#          +-- r-n Integer32    systemLoadLastFive(3)
#          +-- r-n Integer32    systemLoadLastFifteen(4)
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
