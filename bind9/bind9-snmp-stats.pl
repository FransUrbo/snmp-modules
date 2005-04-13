#!/usr/bin/perl

# Based on 'parse_bind9stat.pl' by
# Dobrica Pavlinusic, <dpavlin@rot13.org> 
# http://www.rot13.org/~dpavlin/sysadm.html 

use strict; 


# ---------- !! V A R I A B L E  D E F I N I T I O N S !!

$ENV{PATH}   = "/bin:/usr/bin:/usr/sbin";

my $OID_BASE = ".1.3.6.1.4.1.8767.2.1";	# .iso.org.dod.internet.private.enterprises.bayourcom.snmp.bind9stats

my $log      = "/var/lib/named/var/log/dns-stats.log";
my $rndc     = "/usr/sbin/rndc"; 
my $delta    = "/var/tmp/"; 

my $debug    = 0;
my $arg      = '';

my %DATA;
my %counters     = ("1" => 'success',
		    "2" => 'referral',
		    "3" => 'nxrrset',
		    "4" => 'nxdomain',
		    "5" => 'recursion',
		    "6" => 'failure');

my %types        = ("1" => 'total',
		    "2" => 'forward',
		    "3" => 'reverse');

my %prints_total = ("1" => "TotalsIndex",
		    "2" => "CounterName",
		    "3" => "CounterTotal",
		    "4" => "CounterForward",
		    "5" => "CounterReverse");

# ---------- !! P R E - S T A R T U P !!

#if(!$ENV{"PS1"} && open(DBG, ">> /tmp/bind9-stats.dbg")) {
#    foreach (@ARGV) {
#	print DBG $_."\n";
#    }
#    print DBG "------\n";
#    close(DBG);
#}

# How many base counters?
my $count_counters;
foreach (keys %counters) {
    $count_counters++;
}

# How many types in each counter?
my $count_types;
foreach (keys %types) {
    $count_types++;
}

# ---------- !! S U P P O R T  F U N C T I O N S !!

# man snmpd.conf: string, integer, unsigned, objectid, timeticks, ipaddress, counter, or gauge

sub print_b9stNumberTotals {
    my $j = shift;

    if($debug) {
	print "----- OID_BASE.b9stNumber.0\n";
	print "$OID_BASE.1.0	$count_counters\n\n";
    } else {
	print "$OID_BASE.1.0\n";
	print "integer\n";
	print "$count_counters\n";
    }
}

sub print_b9stTotalsIndex {
    my $j = shift;
    my %cnts;

    if($j) {
	print "----- OID_BASE.b9stTotalsTable.b9stIndexTotals.$j\n" if($debug);
	%cnts = ($j => $counters{$j});
    } else {
	print "----- OID_BASE.b9stTotalsTable.b9stIndexTotals.x\n" if($debug);
	%cnts = %counters;
    }

    foreach $j (keys %cnts) {
	if($debug) {
	    print "$OID_BASE.3.1.1.$j	$j\n";
	} else {
	    print "$OID_BASE.3.1.1.$j\n";
	    print "integer\n";
	    print "$j\n";
	}
    }

    print "\n" if($debug);
}

sub print_b9stCounterName {
    my $j = shift;
    my %cnts;

    if($j) {
	print "----- OID_BASE.b9stTotalsTable.b9stCounterName.$j\n" if($debug);
	%cnts = ($j => $counters{$j});
    } else {
	print "----- OID_BASE.b9stTotalsTable.b9stCounterName.x\n" if($debug);
	%cnts = %counters;
    }

    foreach $j (keys %cnts) {
	if($debug) {
	    print "$OID_BASE.3.1.2.$j	",$counters{$j},"\n";
	} else {
	    print "$OID_BASE.3.1.2.$j\n";
	    print "string\n";
	    print $counters{$j},"\n";
	}
    }

    print "\n" if($debug);
}

sub print_b9stCounterType {
    my $type = shift;
    my $j    = shift;

    my %cnts;
    if($j) {
	%cnts    = ($j => $counters{$j});
    } else {
	%cnts = %counters;
    }

    my $nr = 0;
    my $type_nr = 0;
    foreach $nr (keys %types) {
	if($types{$nr} eq $type) {
	    # .1   => Index
	    # .2   => CounterName
	    # .3-5 => CounterType
	    $type_nr = $nr + 2;
	    last;
	}
    }

    my $type_name = ucfirst($types{$type_nr-2});
    print "----- OID_BASE.b9stTotalsTable.b9stCounter$type_name.x\n" if($debug);

    my $counter;
    foreach $nr (keys %cnts) {
	$counter  = $counters{$nr};

	if($debug) {
	    print "$OID_BASE.3.1.$type_nr.$nr	",$DATA{$counter}{$type},"\n";
	} else {
	    print "$OID_BASE.3.1.$type_nr.$nr\n";
	    print "counter32\n";
	    print $DATA{$counter}{$type},"\n";
	}
    }

    print "\n" if($debug);
}

sub print_b9stCounterTotal {
    my $j = shift;
    &print_b9stCounterType("total", $j);
}

sub print_b9stCounterForward {
    my $j = shift;
    &print_b9stCounterType("forward", $j);
}

sub print_b9stCounterReverse {
    my $j = shift;
    &print_b9stCounterType("reverse", $j);
}

sub print_b9stCounterDomain {
    my $domain = shift;
    my $type   = shift;

    # TODO
}

sub call_func {
    my $func_nr  = shift;
    my $func_arg = shift;
    
    my $func = "print_b9st".$prints_total{$func_nr};
    print "=> Calling function '$func($func_arg)'\n" if($debug);

    $func = \&{$func}; # Because of 'use strict' above...
    &$func($func_arg);
}

# ---------- !! G E T  D A T A !!

system "$rndc stats";

my %total;
my %forward;
my %reverse;

my $tmp=$log;
$tmp=~s/\W/_/g;
$delta.=$tmp.".offset";

open(DUMP, $log) || die "$log: $!";

if (-e $delta) {
    open(D, $delta) || die "can't open delta file '$delta' for '$log': $!";
    my $file_offset = <D>;
    chomp $file_offset;
    close(D);
    my $log_size = -s $log;
    if ($file_offset <= $log_size) {
	seek(DUMP, $file_offset, 0);
    }
}

while(<DUMP>) {
    next if /^(---|\+\+\+)/;
    chomp;
    my ($what, $nr, $domain, $direction) = split(/\s+/, $_, 4);

    if (!$domain) {
	$DATA{$what}{"total"} += $nr;
    } else {
	$DATA{$domain}{$what} = $nr;

	if ($domain =~ m/in-addr.arpa/) {
	    $DATA{$what}{"reverse"} += $nr;
	} else {
	    $DATA{$what}{"forward"} += $nr;
	}
    }
} 

open(D,"> $delta") || die "can't open delta file '$delta' for log '$log': $!"; 
print D tell(DUMP); 
close(D); 

close(DUMP); 

# ---------- !! P R O C E S S  A R G S !!

#my $i;
for(my $i=0; $ARGV[$i]; $i++) {
    if($ARGV[$i] eq '--help' || $ARGV[$i] eq '-h' || $ARGV[$i] eq '?' ) {
	&help();
    } elsif($ARGV[$i] eq '--debug' || $ARGV[$i] eq '-d') {
	$debug = 1;
    } elsif($ARGV[$i] eq '--all' || $ARGV[$i] eq '-a') {
	# All total counters
	my $j;
	foreach $j (keys %prints_total) {
	    &call_func($j, 0);
	}

	# All domain counters
	# TODO
	exit 0;
    } else {
	my $arg = $ARGV[$i];
	print "=> arg=$arg\n" if($debug);

	# $arg == -n => Get next OID		($ARGV[$i+1])
	# $arg == -g => Get specified OID	($ARGV[$i+1])
	$i++;

	print "=> count_counters=$count_counters, count_types=$count_types\n" if($debug);

	my $tmp = $ARGV[$i];
	$tmp =~ s/$OID_BASE//;

	print "=> tmp(1)=$tmp\n" if($debug);
	if($tmp =~ /^\.1/) {
	    # ------------------------------------- OID_BASE.1		(b9stNumberTotals)
	    if($arg eq '-n') {
		# OID_BASE.b9stIndex.1
		&call_func(1, 1);
	    
		exit 0;
	    } else {
		&print_b9stNumberTotals(0);

		exit 0;
	    }
	} elsif($tmp =~ /^\.3/) {
	    # ------------------------------------- OID_BASE.3		(b9stTotalsTable)
	    $tmp =~ s/\.3\.1//; $tmp =~ s/\.//;
	    my @tmp = split('\.', $tmp);
	    print "=> .3.1: tmp0=",$tmp[0],", tmp1=",$tmp[1],"\n" if($debug);

	    if($arg eq '-n') {
		if(!$tmp) {
		    &call_func($tmp[0], $tmp[1]);
		    
		    exit 0;
		} else {
		    # OID_BASE.b9stCounterReverse.x
		    my $x = $tmp[1] + 1;
		    
		    if($x > $count_counters) {
			if($prints_total{$tmp[0]+1}) {
			    &call_func($tmp[0]+1, 1);
			} else {
			    print "No more values\n" if($debug);
			    exit 1;
			}
		    } else {
			&call_func($tmp[0], $tmp[1]+1);
			exit 0;
		    }
		}
	    } elsif($tmp && $prints_total{$tmp[0]}) {
		&call_func($tmp[0], $tmp[1]);
		exit 0;
	    } else {
		print "No value in this object - exiting!\n" if($debug);
		exit 1;
	    }
#	} elsif($tmp =~ /^\.4/) {
#	    # ------------------------------------- OID_BASE.4		(b9stDomainsTable)
	} else {
	    if($arg eq '-n') {
		&print_b9stNumberTotals(0);
		exit 0;
	    } else {
		print "No value in this object - exiting!\n" if($debug);
		exit 1;
	    }
	}
    }
}
