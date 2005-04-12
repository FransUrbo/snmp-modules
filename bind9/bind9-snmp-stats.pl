#!/usr/bin/perl

# Based on 'parse_bind9stat.pl' by
# Dobrica Pavlinusic, <dpavlin@rot13.org> 
# http://www.rot13.org/~dpavlin/sysadm.html 

use strict; 
$ENV{PATH}   = "/bin:/usr/bin:/usr/sbin";

my $OID_BASE = ".1.3.6.1.4.1.8767.2.1";	# .iso.org.dod.internet.private.enterprises.bayourcom.snmp.bind9stats

my $log      = "/var/lib/named/var/log/dns-stats.log";
my $rndc     = "/usr/sbin/rndc"; 
my $delta    = "/var/tmp/"; 

my $debug    = 0;
my $arg      = '';

my %DATA;
my $counter;
my $type;

# Temporary counters...
my $i=0;
my $j=0;
my $k=0;

my $nr_count;
my $nr_type;

my @counters;
my %counters = ("1" => 'success',
		"2" => 'referral',
		"3" => 'nxrrset',
		"4" => 'nxdomain',
		"5" => 'recursion',
		"6" => 'failure');

my @types;
my %types    = ("1" => 'total',
		"2" => 'forward',
		"3" => 'reverse');

# ----------

if(!$ENV{"PS1"} && open(DBG, ">> /tmp/bind9-stats.dbg")) {
    foreach (@ARGV) {
	print DBG $_."\n";
    }
    print DBG "------\n";
    close(DBG);
}

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

# ----------

# man snmpd.conf: string, integer, unsigned, objectid, timeticks, ipaddress, counter, or gauge

sub print_b9stNumber {
    my $tot = shift;

    if($debug) {
	print "----- OID_BASE.b9stNumber.0\n";
	print "$OID_BASE.1.0	$tot\n\n";
    } else {
	print "$OID_BASE.1.0\n";
	print "integer\n";
	print "$tot\n";
    }
}

sub print_b9stIndex {
    my $j = shift;
    my %cnts;

    if($j) {
	print "----- OID_BASE.b9stIndex.$j\n" if($debug);
	%cnts = ($j => $counters{$j});
    } else {
	print "----- OID_BASE.b9stIndex.x\n" if($debug);
	%cnts = %counters;
    }

    foreach $j (keys %cnts) {
	if($debug) {
	    print "$OID_BASE.2.1.1.$j	$j\n";
	} else {
	    print "$OID_BASE.2.1.1.$j\n";
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
	print "----- OID_BASE.b9stCounterName.$j\n" if($debug);
	%cnts = ($j => $counters{$j});
    } else {
	print "----- OID_BASE.b9stCounterName.x\n" if($debug);
	%cnts = %counters;
    }

    foreach $j (keys %cnts) {
	if($debug) {
	    print "$OID_BASE.2.1.2.$j	",$counters{$j},"\n";
	} else {
	    print "$OID_BASE.2.1.2.$j\n";
	    print "string\n";
	    print $counters{$j},"\n";
	}
    }

    print "\n" if($debug);
}

sub print_b9stCounterType {
    my $type = shift;
    my $j    = shift;

    my $counter;
    my %cnts;
    my $type_nr = 0;

    if($j) {
	%cnts    = ($j => $counters{$j});
    } else {
	%cnts = %counters;
    }

    foreach $j (keys %types) {
	if($types{$j} eq $type) {
	    # .1   => Index
	    # .2   => CounterName
	    # .3-5 => CounterType
	    $type_nr = $j + 2;
	    last;
	}
    }

    print "----- OID_BASE.b9stCounterType.$type_nr.x (",$types{$j},")\n" if($debug);
    foreach $j (keys %cnts) {
	$counter  = $counters{$j};

	if($debug) {
	    print "$OID_BASE.2.1.$type_nr.$j	",$DATA{$counter}{$type},"\n";
	} else {
	    print "$OID_BASE.2.1.$type_nr.$j\n";
	    print "counter\n";
	    print $DATA{$counter}{$type},"\n";
	}
    }

    print "\n" if($debug);
}

# ----------

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
    my ($what, $nr, $direction) = split(/\s+/, $_, 3); 
    if (! $direction) { 
	$DATA{$what}{"total"} += $nr; 
    } elsif ($direction =~ m/in-addr.arpa/) { 
	$DATA{$what}{"reverse"} += $nr; 
    } else { 
	$DATA{$what}{"forward"} += $nr; 
    } 

} 

open(D,"> $delta") || die "can't open delta file '$delta' for log '$log': $!"; 
print D tell(DUMP); 
close(D); 

close(DUMP); 

# ----------

for($i=0; $ARGV[$i]; $i++) {
    if($ARGV[$i] eq '--help' || $ARGV[$i] eq '-h' || $ARGV[$i] eq '?' ) {
	&help();
    } elsif($ARGV[$i] eq '--debug' || $ARGV[$i] eq '-d') {
	$debug = 1;
    } elsif($ARGV[$i] eq '--all' || $ARGV[$i] eq '-a') {
	for($k=0, $j=1; $j <= $count_counters; $k++, $j++) {
	    $counters[$k] = $j;
	}

	for($k=0, $j=1; $j <= $count_types; $k++, $j++) {
	    $types[$k] = $j;
	}

	undef @ARGV; # Quit here, don't go further
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
	    # ------------------------------------- OID_BASE.1		(b9stNumber)
	    if($arg eq '-n') {
		# OID_BASE.b9stIndex.1
		&print_b9stIndex(1);
	    
		exit 0;
	    } else {
		&print_b9stNumber($count_counters);

		exit 0;
	    }
	} elsif($tmp =~ /^\.2\.1\.1/) {
	    # ------------------------------------- OID_BASE.2.1.1	(b9stIndex)
	    $tmp =~ s/\.2\.1\.1//; $tmp =~ s/\.//;
	    print "=> .2.1.1: tmp=$tmp\n" if($debug);

	    my $x;
	    if($arg eq '-n') {
		if(!$tmp) {
		    # OID_BASE.b9stIndex.1
		    &print_b9stIndex(1);
		    
		    exit 0;
		} else {
		    # OID_BASE.b9stIndex.x
		    $x = $tmp + 1;
		    
		    if($x > $count_counters) {
			# NEXT: OID_BASE.b9stCounterName.1
			&print_b9stCounterName(1);
			
			exit 0;
		    } else {
			&print_b9stIndex($x);
			exit 0;
		    }
		}
	    } elsif($tmp) {
		&print_b9stIndex($tmp);
		exit 0;
	    } else {
		print "No value in this object - exiting!\n" if($debug);
		exit 1;
	    }
	} elsif($tmp =~ /^\.2\.1\.2/) {
	    # ------------------------------------- OID_BASE.2.1.2	(b9stCounterName)
	    $tmp =~ s/\.2\.1\.2//; $tmp =~ s/\.//;
	    print "=> .2.1.2: tmp=$tmp\n" if($debug);

	    my $x;
	    if($arg eq '-n') {
		if(!$tmp) {
		    # OID_BASE.b9stCounterName.1
		    &print_b9stCounterName(1);
		    
		    exit 0;
		} else {
		    # OID_BASE.b9stCounterName.x
		    $x = $tmp + 1;
		    
		    if($x > $count_counters) {
			# NEXT: OID_BASE.b9stCounterTotal.1
			&print_b9stCounterType("total", 1);
			
			exit 0;
		    } else {
			&print_b9stCounterName($x);
			exit 0;
		    }
		}
	    } elsif($tmp) {
		&print_b9stCounterName($tmp);
		exit 0;
	    } else {
		print "No value in this object - exiting!\n" if($debug);
		exit 1;
	    }
	} elsif($tmp =~ /^\.2\.1\.3/) {
	    # ------------------------------------- OID_BASE.2.1.3	(b9stCounterTotal)
	    $tmp =~ s/\.2\.1\.3//; $tmp =~ s/\.//;
	    print "=> .2.1.3: tmp=$tmp\n" if($debug);

	    my $x;
	    if($arg eq '-n') {
		if(!$tmp) {
		    # OID_BASE.b9stCounterTotal.1
		    &print_b9stCounterType("total", 1);
		    
		    exit 0;
		} else {
		    # OID_BASE.b9stCounterTotal.x
		    $x = $tmp + 1;
		    
		    if($x > $count_counters) {
			# NEXT: OID_BASE.b9stCounterForward.1
			&print_b9stCounterType("forward", 1);
			
			exit 0;
		    } else {
			&print_b9stCounterType("total", $x);
			exit 0;
		    }
		}
	    } elsif($tmp) {
		&print_b9stCounterType("total", $tmp);
		exit 0;
	    } else {
		print "No value in this object - exiting!\n" if($debug);
		exit 1;
	    }
	} elsif($tmp =~ /^\.2\.1\.4/) {
	    # ------------------------------------- OID_BASE.2.1.4	(b9stCounterForward)
	    $tmp =~ s/\.2\.1\.4//; $tmp =~ s/\.//;
	    print "=> .2.1.4: tmp=$tmp\n" if($debug);

	    my $x;
	    if($arg eq '-n') {
		if(!$tmp) {
		    # OID_BASE.b9stCounterForward.1
		    &print_b9stCounterType("forward", 1);
		    
		    exit 0;
		} else {
		    # OID_BASE.b9stCounterForward.x
		    $x = $tmp + 1;
		    
		    if($x > $count_counters) {
			# NEXT: OID_BASE.b9stCounterReverse.1
			&print_b9stCounterType("reverse", 1);
			
			exit 0;
		    } else {
			&print_b9stCounterType("forward", $x);
			exit 0;
		    }
		}
	    } elsif($tmp) {
		&print_b9stCounterType("forward", $tmp);
		exit 0;
	    } else {
		print "No value in this object - exiting!\n" if($debug);
		exit 1;
	    }
	} elsif($tmp =~ /^\.2\.1\.5/) {
	    # ------------------------------------- OID_BASE.2.1.5	(b9stCounterReverse)
	    $tmp =~ s/\.2\.1\.5//; $tmp =~ s/\.//;
	    print "=> .2.1.5: tmp=$tmp\n" if($debug);

	    my $x;
	    if($arg eq '-n') {
		if(!$tmp) {
		    # OID_BASE.b9stCounterReverse.1
		    &print_b9stCounterType("reverse", 1);
		    
		    exit 0;
		} else {
		    # OID_BASE.b9stCounterReverse.x
		    $x = $tmp + 1;
		    
		    if($x > $count_counters) {
			# NEXT: VOID
			print "No value in this object - exiting!\n" if($debug);
			exit 1;
		    } else {
			&print_b9stCounterType("reverse", $x);
			exit 0;
		    }
		}
	    } elsif($tmp) {
		&print_b9stCounterType("reverse", $tmp);
		exit 0;
	    } else {
		print "No value in this object - exiting!\n" if($debug);
		exit 1;
	    }
	} else {
	    if($arg eq '-n') {
		&print_b9stNumber($count_counters);
		exit 0;
	    } else {
		print "No value in this object - exiting!\n" if($debug);
		exit 1;
	    }
	}
    }
}
