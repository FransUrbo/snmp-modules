#!/usr/bin/perl -w

# {{{ $Id: system-snmp-stats.pl,v 1.3 2006-04-25 11:14:02 turbo Exp $
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
#	OS=linux
#
# PS for ! Linux:
#	The function get_memstats_linux() opens /proc/meminfo
#	to retreive memory information of the system. This file
#	is _most likley_ not portable through *IX like systems...
#	If you're not running Linux and you'd like support for this
#	in your OS, then write your own function. Don't forget to
#	update this documentation and the get_memstats() function
#	wrapper...
#
# }}}

# {{{ Include libraries and setup global variables
# Forces a buffer flush after every print
$|=1;

use strict; 
use POSIX qw(strftime);
use BayourCOM_SNMP;

$ENV{PATH} = "/bin:/usr/bin:/usr/sbin";

my $OID_BASE;
$OID_BASE = "OID_BASE"; # When debugging, it's easier to type this than the full OID
if($ENV{'MIBDIRS'}) {
    # ALWAYS override this if we're running through the SNMP daemon!
    $OID_BASE = ".1.3.6.1.4.1.8767.2.4"; # .iso.org.dod.internet.private.enterprises.bayourcom.snmp.systemStats
}

# The input OID
my($oid);

my %DATA;
my @retreives = ('get_uptime', 'get_memstats', 'get_cpuusage', 'get_loadavg');

my %prints    = ( '1' => 'print_uptime',
		  '2' => 'print_memstats',
		  '3' => 'print_cpuusage',
		  '4' => 'print_loadavg');

my %memstats  = ('02' => 'total',
		 '03' => 'used',
		 '04' => 'free',
		 '05' => 'buffers',
		 '06' => 'cached',
		 '07' => 'swaptotal',
		 '08' => 'swapused',
		 '09' => 'swapfree');

my %cpustats  = ('10' => 'idle',
		 '11' => 'nice',
		 '12' => 'syst',
		 '13' => 'user');

my %loastats  = ('14' => 'load_01',
		 '15' => 'load_05',
		 '16' => 'load_15');

# handle a SIGALRM - read statistics file
$SIG{'ALRM'} = \&load_information;
# }}}

# {{{ OID tree
# smidump -f tree BAYOUR-COM-MIB.txt
#  +--systemStats(4)
#     +-- r-n Integer32 systemUptime(1)
#     |
#     +-- r-n Integer32 systemMemoryTotal(2)
#     +-- r-n Integer32 systemMemoryUsed(3)
#     +-- r-n Integer32 systemMemoryFree(4)
#     +-- r-n Integer32 systemMemoryBuffered(5)
#     +-- r-n Integer32 systemMemoryCached(6)
#     +-- r-n Integer32 systemMemorySwapTotal(7)
#     +-- r-n Integer32 systemMemorySwapUsed(8)
#     +-- r-n Integer32 systemMemorySwapFree(9)
#     |
#     +-- r-n Integer32 systemCPUTasksTotal(10)
#     +-- r-n Integer32 systemCPUTasksRunning(11)
#     +-- r-n Integer32 systemCPUTasksSleeping(12)
#     +-- r-n Integer32 systemCPUTasksStopped(13)
#     +-- r-n Integer32 systemCPUTasksZombies(14)
#     +-- r-n Integer32 systemCPUUsageUser(15)
#     +-- r-n Integer32 systemCPUUsageSystem(16)
#     +-- r-n Integer32 systemCPUUsageNice(17)
#     +-- r-n Integer32 systemCPUUsageIdle(18)
#     +-- r-n Integer32 systemCPUUsageIOWait(19)
#     |
#     +-- r-n Integer32 systemLoadLastOne(20)
#     +-- r-n Integer32 systemLoadLastFive(21)
#     +-- r-n Integer32 systemLoadLastFifteen(22)
# }}}

# ====================================================
# =====    R E T R E I V E  F U N C T I O N S    =====

# {{{ get_uptime
# Returns hours of uptime
sub get_uptime {
    my($uptime, $days, $hours, $mins, @tmp);

    $uptime = `uptime`;
    @tmp    = split(' ', $uptime);
    
    $days   = $tmp[2];
    $hours  = (split(':', $tmp[4]))[0];
    $mins   = (split(':', $tmp[4]))[1]; $mins   =~ s/,$//;
    
    $DATA{'uptime'} = ((($days * 24) + $hours) * 60) + $mins; # total in minutes
    debug(0, "get_uptime: '".$DATA{'uptime'}."'\n");
}
# }}}

# {{{ get_memstats
sub get_memstats {
    if($CFG{'OS'} eq 'linux') {
	return get_memstats_linux();
    } else {
	# Unknown OS!
	return 0;
    }
}

sub get_memstats_linux {
    my($line);

    open(MEM, "/proc/meminfo") || die("Can't open /proc/meminfo: $!\n");
    while(!eof(MEM)) {
	$line = <MEM>; chomp($line);
	$line =~ s/ kB$//;
	$line =~ s/ //g;
	
	if($line =~ /^MemTotal:/) {
	    $DATA{'mem'}{'total'} = (split(':', $line))[1];
	    debug(0, "get_memstats_linux: total=".$DATA{'mem'}{'total'}."\n");

	} elsif($line =~ /^MemFree:/) {
	    $DATA{'mem'}{'free'} = (split(':', $line))[1];
	    debug(0, "get_memstats_linux: free=".$DATA{'mem'}{'free'}."\n");

	} elsif($line =~ /^Buffers:/) {
	    $DATA{'mem'}{'buffers'} = (split(':', $line))[1];
	    debug(0, "get_memstats_linux: buffers=".$DATA{'mem'}{'buffers'}."\n");

	} elsif($line =~ /^Cached:/) {
	    $DATA{'mem'}{'cached'} = (split(':', $line))[1];
	    debug(0, "get_memstats_linux: cached=".$DATA{'mem'}{'cached'}."\n");

	} elsif($line =~ /^SwapTotal:/) {
	    $DATA{'mem'}{'swaptotal'} = (split(':', $line))[1];
	    debug(0, "get_memstats_linux: swaptotal=".$DATA{'mem'}{'swaptotal'}."\n");

	} elsif($line =~ /^SwapFree:/) {
	    $DATA{'mem'}{'swapfree'} = (split(':', $line))[1];
	    debug(0, "get_memstats_linux: swapfree=".$DATA{'mem'}{'swapfree'}."\n");

	}
    }
    close(MEM);

    if($DATA{'mem'}{'total'} && $DATA{'mem'}{'free'}) {
	$DATA{'mem'}{'used'} = $DATA{'mem'}{'total'} - $DATA{'mem'}{'free'};
	debug(0, "get_memstats_linux: used=".$DATA{'mem'}{'used'}."\n");
    }

    if($DATA{'mem'}{'swaptotal'} && $DATA{'mem'}{'swapfree'}) {
	$DATA{'mem'}{'swapused'} = $DATA{'mem'}{'swaptotal'} - $DATA{'mem'}{'swapfree'};
	debug(0, "get_memstats_linux: swapused=".$DATA{'mem'}{'swapused'}."\n");
    }
}
# }}}

# {{{ get_cpuusage
sub get_cpuusage {
    my($line, $TYPE, @tmp);

    open(TOP, "/usr/bin/top n 1 b |") || die("Can't start top: $!\n");
    while(!eof(TOP)) {
	$line = <TOP>; chomp($line);
	if(($line =~ /^CPU states/) || ($line =~ /^Cpu\(s\)/)) {
	    close(TOP);
	    
	    if($line =~ /^CPU states/) {
		$TYPE = 'old';
	    } elsif($line =~ /^Cpu\(s\)/) {
		$TYPE = 'new';
	    }
	    
	    last;
	}
    }
    
    $line =~ s/%//g;
    
    @tmp = split(' ', $line);
    if($TYPE eq 'old') {
	$DATA{'cpu'}{'idle'} = $tmp[8];
	$DATA{'cpu'}{'nice'} = $tmp[6];
	$DATA{'cpu'}{'syst'} = $tmp[4];
	$DATA{'cpu'}{'user'} = $tmp[2];
    } elsif($TYPE eq 'new') {
	$DATA{'cpu'}{'user'} = $tmp[1];
	$DATA{'cpu'}{'syst'} = $tmp[3];
	$DATA{'cpu'}{'nice'} = $tmp[5];
	$DATA{'cpu'}{'idle'} = $tmp[7];
    } else {
	print "Unknown TYPE!";
	exit 1;
    }

    debug(0, "get_cpuusage: idle=".$DATA{'cpu'}{'idle'}."\n");
    debug(0, "get_cpuusage: nice=".$DATA{'cpu'}{'nice'}."\n");
    debug(0, "get_cpuusage: syst=".$DATA{'cpu'}{'syst'}."\n");
    debug(0, "get_cpuusage: user=".$DATA{'cpu'}{'user'}."\n");
}
# }}}

# {{{ get_loadavg
sub get_loadavg {
    my($line);

    open(LOAD, "/proc/loadavg") || die("Can't open /proc/loadavg: $!\n");
    while(!eof(LOAD)) {
	$line = <LOAD>; chomp($line);

	$DATA{'loa'}{'load_01'} = (split(' ', $line))[0];
	$DATA{'loa'}{'load_05'} = (split(' ', $line))[1];
	$DATA{'loa'}{'load_15'} = (split(' ', $line))[2];
    }
    close(LOAD);

    debug(0, "get_loadavg: load_01=".$DATA{'loa'}{'load_01'}."\n");
    debug(0, "get_loadavg: load_05=".$DATA{'loa'}{'load_05'}."\n");
    debug(0, "get_loadavg: load_15=".$DATA{'loa'}{'load_15'}."\n");
}
# }}}

# ====================================================
# =====       P R I N T  F U N C T I O N S       =====

# {{{ print_uptime	-> OID_BASE.1
sub print_uptime {
    debug(0, "$OID_BASE.1 = ".$DATA{'uptime'}."\n") if($CFG{'DEBUG'});

    debug(1, "$OID_BASE.1\n");
    debug(1, "integer\n");
    debug(1, $DATA{'uptime'}."\n");

    debug(0, "\n");
}
# }}}

# {{{ print_memstats	-> OID_BASE.[ 2- 9]
sub print_memstats {
    my $j = shift;

    if($j) {
	# One specific counter
	my $key = $memstats{$j};
	
	debug(0, "$OID_BASE.$j = ".$DATA{'mem'}{$key}."\n") if($CFG{'DEBUG'});
	
	debug(1, "$OID_BASE.$j\n");
	debug(1, "integer\n");
	debug(1, $DATA{'mem'}{$key}."\n");
    } else {
	# ALL counters
	foreach my $j (sort keys %memstats) {
	    my $key = $memstats{$j};
	    $j =~ s/^0//;

	    debug(0, "$OID_BASE.$j = ".$DATA{'mem'}{$key}."\n") if($CFG{'DEBUG'});
	    
	    debug(1, "$OID_BASE.$j\n");
	    debug(1, "integer\n");
	    debug(1, $DATA{'mem'}{$key}."\n");
	}
    }

    debug(0, "\n");
}
# }}}

# {{{ print_cpuusage	-> OID_BASE.[10-13]
sub print_cpuusage {
    my $j = shift;

    if($j) {
	# One specific counter
	my $key = $cpustats{$j};
	
	debug(0, "$OID_BASE.$j = ".$DATA{'cpu'}{$key}."\n") if($CFG{'DEBUG'});
	
	debug(1, "$OID_BASE.$j\n");
	debug(1, "integer\n");
	debug(1, $DATA{'cpu'}{$key}."\n");
    } else {
	# ALL counters
	foreach my $j (sort keys %cpustats) {
	    my $key = $cpustats{$j};

	    debug(0, "$OID_BASE.$j = ".$DATA{'cpu'}{$key}."\n") if($CFG{'DEBUG'});
	    
	    debug(1, "$OID_BASE.$j\n");
	    debug(1, "integer\n");
	    debug(1, $DATA{'cpu'}{$key}."\n");
	}
    }

    debug(0, "\n");
}
# }}}

# {{{ print_loadavg	-> OID_BASE.[14-16]
sub print_loadavg {
    my $j = shift;

    if($j) {
	# One specific counter
	my $key = $loastats{$j};
	
	debug(0, "$OID_BASE.$j = ".$DATA{'loa'}{$key}."\n") if($CFG{'DEBUG'});
	
	debug(1, "$OID_BASE.$j\n");
	debug(1, "integer\n");
	debug(1, $DATA{'loa'}{$key}."\n");
    } else {
	# ALL counters
	foreach my $j (sort keys %loastats) {
	    my $key = $loastats{$j};

	    debug(0, "$OID_BASE.$j = ".$DATA{'loa'}{$key}."\n") if($CFG{'DEBUG'});
	    
	    debug(1, "$OID_BASE.$j\n");
	    debug(1, "integer\n");
	    debug(1, $DATA{'loa'}{$key}."\n");
	}
    }

    debug(0, "\n");
}
# }}}

# ====================================================
# =====        M I S C  F U N C T I O N S        =====

# {{{ call_func
sub call_func {
    my $func_nr  = shift;
    my $func_arg = shift;

    my $func = $prints{$func_nr};
    $func_arg = '' if(!defined($func_arg));
    debug(0, "=> Calling function '$func($func_arg)'\n") if($CFG{'DEBUG'} > 3);

    $func = \&{$func}; # Because of 'use strict' above...
    &$func($func_arg);
}
# }}}

# {{{ load_information
sub load_information {
    my($func_arg, $func);

    # Load configuration file
    %CFG = get_config($CFG_FILE);

    debug(0, "=> OID_BASE => '$OID_BASE'\n");

    foreach my $func (@retreives) {
	$func_arg = '' if(!defined($func_arg));

	debug(0, "=> Calling function '$func($func_arg)'\n") if($CFG{'DEBUG'} > 3);
	$func = \&{$func}; # Because of 'use strict' above...
	&$func($func_arg);
	debug(0, "\n");
    }

    # Schedule an alarm once every five minutes to re-read information.
    alarm(5*60);
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
    foreach my $nr (sort keys %prints) {
	call_func($nr);
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
	$CFG{'DEBUG'} = get_config($CFG_FILE, 'DEBUG');

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
	debug(0, "=> ARG='$arg  $OID_BASE.$oid'\n") if($CFG{'DEBUG'} >= 2);
	
	my @tmp = split('\.', $oid);
	output_extra_debugging(@tmp) if($CFG{'DEBUG'} > 2);
# }}}

	if($arg eq 'getnext') {
	    # {{{ Get next OID
# }}}
	} elsif($arg eq 'get') {
	    # {{{ Get _this_ OID
# }}}
	}

	debug(0, "\n") if($CFG{'DEBUG'} > 1);
    }
# }}}
}
