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
my %DOMAINS;

my %counters       = ("1" => 'success',
		      "2" => 'referral',
		      "3" => 'nxrrset',
		      "4" => 'nxdomain',
		      "5" => 'recursion',
		      "6" => 'failure');

my %types          = ("1" => 'total',
		      "2" => 'forward',
		      "3" => 'reverse');

my %prints_total   = ("1" => "TotalsIndex",
		      "2" => "CounterName",
		      "3" => "CounterTotal",
		      "4" => "CounterForward",
		      "5" => "CounterReverse");

my $count_domains  = 0;
my %prints_domain  = ("1" => "DomainsIndex",
		      "2" => "DomainName",
		      "3" => "CounterSuccess",
		      "4" => "CounterReferral",
		      "5" => "CounterNXRRSet",
		      "6" => "CounterNXDomain",
		      "7" => "CounterRecursion",
		      "8" => "CounterFailure");

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

# --------------
# Show usage
sub help {
    my $name = `basename $0`; chomp($name);

    print "Usage: $name [option] [oid]\n";
    print "Options: --debug|-d  Run in debug mode\n";
    print "         --all|-a    Get all information\n";
    print "         -n          Get next OID ('oid' required)\n";
    print "         -g          Get specified OID ('oid' required)\n";

    exit 1;
}

sub print_b9stNumberTotals {
    my $j = shift;

    if($debug) {
	print "----- OID_BASE.b9stNumberTotals.0\n";
	print "$OID_BASE.1.0	$count_counters\n\n";
    } else {
	print "$OID_BASE.1.0\n";
	print "integer\n";
	print "$count_counters\n";
    }
}

sub print_b9stNumberDomains {
    my $j = shift;

    if($debug) {
	print "----- OID_BASE.b9stNumberDomains.0\n";
	print "$OID_BASE.2.0	$count_domains\n\n";
    } else {
	print "$OID_BASE.2.0\n";
	print "integer\n";
	print "$count_domains\n";
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

sub print_b9stCounterTypeTotal {
    my $type = shift;
    my $j    = shift;

    my %cnts;
    if($j) {
	%cnts = ($j => $counters{$j});
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
    &print_b9stCounterTypeTotal("total", $j);
}

sub print_b9stCounterForward {
    my $j = shift;
    &print_b9stCounterTypeTotal("forward", $j);
}

sub print_b9stCounterReverse {
    my $j = shift;
    &print_b9stCounterTypeTotal("reverse", $j);
}

sub print_b9stDomainsIndex {
    my $j = shift;
    my %cnts;

    if($j) {
	print "----- OID_BASE.b9stDomainsTable.b9stIndexDomains.$j\n" if($debug);
	%cnts = ($j => $DOMAINS{$j});
    } else {
	print "----- OID_BASE.b9stDomainsTable.b9stIndexDomains.x\n" if($debug);
	%cnts = %DOMAINS;
    }

    foreach $j (sort keys %cnts) {
	$j =~ s/^0//;

	if($debug) {
	    print "$OID_BASE.4.1.1.$j	$j\n";
	} else {
	    print "$OID_BASE.4.1.1.$j\n";
	    print "integer\n";
	    print "$j\n";
	}
    }

    print "\n" if($debug);
}

sub print_b9stDomainName {
    my $j = shift;
    my %cnts;

    if($j) {
	print "----- OID_BASE.b9stDomainsTable.b9stDomainName.$j\n" if($debug);

	my $i = $j;
	$j = sprintf("%0.2d", $j);

	%cnts = ($j => $DOMAINS{$j});
    } else {
	print "----- OID_BASE.b9stDomainsTable.b9stDomainName.x\n" if($debug);
	%cnts = %DOMAINS;
    }

    foreach my $j (sort keys %cnts) {
	my $domain = (split(':', $cnts{$j}{"success"}))[0];

	$j =~ s/^0//;
	if($debug) {
	    print "$OID_BASE.4.1.2.$j	$domain\n";
	} else {
	    print "$OID_BASE.4.1.2.$j\n";
	    print "string\n";
	    print "$domain\n";
	}
    }

    print "\n" if($debug);
}

sub print_b9stCounterTypeDomains {
    my $type = shift;
    my $j    = shift;

    my %cnts;
    if($j) {
	my $i = $j;
	$j = sprintf("%0.2d", $j);

	%cnts = ($i => $DOMAINS{$j});
    } else {
	%cnts = %DOMAINS;
    }

    my $nr = 0;
    my $type_nr = 0;
    foreach $nr (keys %counters) {
	if($counters{$nr} eq $type) {
	    # .1   => Index
	    # .2   => CounterName
	    # .3-5 => CounterType
	    $type_nr = $nr + 2;
	    last;
	}
    }

    my $type_name = ucfirst($counters{$type_nr-2});
    print "----- OID_BASE.b9stDomainsTable.b9stCounter$type_name.x\n" if($debug);

    foreach my $i (sort keys %cnts) {
	my ($domain, $value) = split(':', $cnts{$i}{$type});

	$i =~ s/^0//;
	if($debug) {
	    print "$OID_BASE.4.1.$type_nr.$i	$value\n";
	} else {
	    print "$OID_BASE.4.1.$type_nr.$i\n";
	    print "counter32\n";
	    print "$value\n";
	}
    }

    print "\n" if($debug);
}

sub print_b9stCounterSuccess {
    my $j = shift;
    &print_b9stCounterTypeDomains("success", $j);
}

sub print_b9stCounterReferral {
    my $j = shift;
    &print_b9stCounterTypeDomains("referral", $j);
}

sub print_b9stCounterNXRRSet {
    my $j = shift;
    &print_b9stCounterTypeDomains("nxrrset", $j);
}

sub print_b9stCounterNXDomain {
    my $j = shift;
    &print_b9stCounterTypeDomains("nxdomain", $j);
}

sub print_b9stCounterRecursion {
    my $j = shift;
    &print_b9stCounterTypeDomains("recursion", $j);
}

sub print_b9stCounterFailure {
    my $j = shift;
    &print_b9stCounterTypeDomains("failure", $j);
}

sub call_func_total {
    my $func_nr  = shift;
    my $func_arg = shift;
    
    my $func = "print_b9st".$prints_total{$func_nr};
    print "=> Calling function '$func($func_arg)'\n" if($debug);

    $func = \&{$func}; # Because of 'use strict' above...
    &$func($func_arg);
}

sub call_func_domain {
    my $func_nr  = shift;
    my $func_arg = shift;
    
    my $func = "print_b9st".$prints_domain{$func_nr};
    print "=> Calling function '$func($func_arg)'\n" if($debug);

    $func = \&{$func}; # Because of 'use strict' above...
    &$func($func_arg);
}

# ---------- !! G E T  D A T A !!

system "$rndc stats" if($rndc);

my %total;
my %forward;
my %reverse;

my $tmp=$log;
$tmp=~s/\W/_/g;
$delta.=$tmp.".offset" if($delta);

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

my %tmp;
while(<DUMP>) {
    next if /^(---|\+\+\+)/;
    chomp;
    my ($what, $nr, $domain, $direction) = split(/\s+/, $_, 4);

    if (!$domain) {
	$DATA{$what}{"total"} += $nr;
    } else {
	$DOMAINS{$domain}{$what} = $nr;

	if ($domain =~ m/in-addr.arpa/) {
	    $DATA{$what}{"reverse"} += $nr;
	} else {
	    $DATA{$what}{"forward"} += $nr;
	}
    }
} 

if($delta) {
    open(D,"> $delta") || die "can't open delta file '$delta' for log '$log': $!"; 
    print D tell(DUMP); 
    close(D); 
}

close(DUMP); 

unlink($log);
unlink($delta);
system "touch /var/lib/named/var/log/dns-stats.log";
system "chown bind9.bind9 /var/lib/named/var/log/dns-stats.log";

# How many domains?
my %tmp1;
my %tmp2;
foreach my $domain (sort keys %DOMAINS) {
    if(!$tmp{$domain}) {
	$count_domains++;

	$tmp{$domain} = $domain;

	foreach my $nr (keys %counters) {
	    my $what = $counters{$nr};
	    my $cnt  = sprintf("%0.2d", $count_domains);
	    
	    $tmp2{$cnt}{$what} = $domain.":".$DOMAINS{$domain}{$what};
	}
    }
}
$count_domains -= 1;

undef(%DOMAINS);
%DOMAINS = %tmp2;

# ---------- !! P R O C E S S  A R G S !!

#my $i;
for(my $i=0; $ARGV[$i]; $i++) {
    if($ARGV[$i] eq '--help' || $ARGV[$i] eq '-h' || $ARGV[$i] eq '?' ) {
	&help();
    } elsif($ARGV[$i] eq '--debug' || $ARGV[$i] eq '-d') {
	$debug = 1;
    } elsif($ARGV[$i] eq '--all' || $ARGV[$i] eq '-a') {
	&print_b9stNumberTotals(0);
	&print_b9stNumberDomains(0);

	foreach my $j (keys %prints_total) {
	    &call_func_total($j, 0);
	}

	foreach my $j (keys %prints_domain) {
	    &call_func_domain($j, 0);
	}

	exit 0;
    } else {
	my $arg = $ARGV[$i];
	print "=> arg=$arg\n" if($debug);

	# $arg == -n => Get next OID		($ARGV[$i+1])
	# $arg == -g => Get specified OID	($ARGV[$i+1])
	$i++;

	print "=> count_counters=$count_counters, count_types=$count_types, count_domains=$count_domains\n" if($debug);

	my $tmp = $ARGV[$i];
	$tmp =~ s/$OID_BASE//;

	print "=> tmp(1)=$tmp\n" if($debug);
	if($tmp =~ /^\.1/) {
	    # ------------------------------------- OID_BASE.1		(b9stNumberTotals)
	    if($arg eq '-n') {
		&print_b9stNumberDomains(0);
		exit 0;
	    } else {
		&print_b9stNumberTotals(0);
		exit 0;
	    }
	} elsif($tmp =~ /^\.2/) {
	    # ------------------------------------- OID_BASE.2		(b9stNumberDomains)
	    if($arg eq '-n') {
		&call_func_total(1, 1);
		exit 0;
	    } else {
		&print_b9stNumberDomains(0);
		exit 0;
	    }
	} elsif($tmp =~ /^\.3/) {
	    # ------------------------------------- OID_BASE.3		(b9stTotalsTable)
	    $tmp =~ s/^\.3//;
	    $tmp =~ s/^\.1//;
	    $tmp =~ s/^\.//;
	    my @tmp = split('\.', $tmp);
	    print "=> .3.1: tmp0=",$tmp[0],", tmp1=",$tmp[1],", tmp2=",$tmp[2],"\n" if($debug);

	    if($arg eq '-n') {
		if(!$tmp[0] && !$tmp[1]) {
		    &call_func_total(1, 1);
		    exit 0;
		} elsif(!$tmp[1]) {
		    &call_func_total($tmp[0], 1);
		    exit 0;
		} else {
		    my $x = $tmp[1] + 1;
		    
		    if($x > $count_counters) {
			if($prints_total{$tmp[0]+1}) {
			    &call_func_total($tmp[0]+1, 1);
			} else {
			    &call_func_domain(1, 1);
			}
		    } else {
			&call_func_total($tmp[0], $tmp[1]+1);
			exit 0;
		    }
		}
	    } elsif($tmp && $prints_total{$tmp[0]}) {
		&call_func_total($tmp[0], $tmp[1]);
		exit 0;
	    } elsif($tmp && $prints_domain{$tmp[0]}) {
		&call_func_domain($tmp[0], $tmp[1]);
		exit 0;
	    } else {
		print "No value in this object - exiting!\n" if($debug);
		exit 1;
	    }
	} elsif($tmp =~ /^\.4/) {
	    # ------------------------------------- OID_BASE.4		(b9stDomainsTable)
	    $tmp =~ s/^\.4//;
	    $tmp =~ s/^\.1//;
	    $tmp =~ s/^\.//;
	    my @tmp = split('\.', $tmp);
	    print "=> .4.1: tmp0=",$tmp[0],", tmp1=",$tmp[1],"\n" if($debug);

	    if($arg eq '-n') {
		if(!$tmp[0] && !$tmp[1]) {
		    &call_func_domain(1, 1);
		    exit 0;
		} elsif(!$tmp[1]) {
		    &call_func_domain($tmp[0], 1);
		    exit 0;
		} else {
		    my $x = $tmp[1] + 1;
		    
		    if($x > $count_domains) {
			if($prints_domain{$tmp[0]+1}) {
			    &call_func_domain($tmp[0]+1, 1);
			} else {
			    print "No more values\n" if($debug);
			    exit 1;
			}
		    } else {
			&call_func_domain($tmp[0], $tmp[1]+1);
			exit 0;
		    }
		}
	    } elsif($tmp && $prints_domain{$tmp[0]}) {
		&call_func_domain($tmp[0], $tmp[1]);
		exit 0;
	    } else {
		print "No more values - exiting!\n" if($debug);
		exit 1;
	    }
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
