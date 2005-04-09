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

my $oidval;

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

    print "$OID_BASE.1.0\n";
    print "integer\n";
    print "$tot\n";
}

sub print_b9stIndex() {
    my $l = 1, $j, $k;

    foreach $j (keys %counters) {
	foreach $k (keys %types) {
	    print $OID_BASE,".2.1.1.$l\n";
	    print "integer\n";
	    print "$l\n";
	    
	    $l++;
	}
    }
}

sub print_b9stDescr() {
    my $l = 1, $j, $k;
    foreach $j (keys %counters) {
	foreach $k (keys %types) {
	    print $OID_BASE,".2.1.2.$l\n";
	    print "string\n";
	    print $counters{$j},":",$types{$k},"\n";
	    
	    $l++;
	}
    }
}

sub y {
    my $x = shift;

    if(     ($x >=  1) && ($x <=  3)) {
	return 1;
    } elsif(($x >=  4) && ($x <=  6)) {
	return 2;
    } elsif(($x >=  7) && ($x <=  9)) {
	return 3;
    } elsif(($x >= 10) && ($x <= 12)) {
	return 4;
    } elsif(($x >= 13) && ($x <= 15)) {
	return 5;
    } elsif(($x >= 16) && ($x <= 18)) {
	return 6;
    }
}

sub z {
    my $x = shift;

    if(     ($x == 1) || ($x == 4) || ($x == 7) || ($x == 10) || ($x == 13) || ($x == 16)) {
	return 1;
    } elsif(($x == 2) || ($x == 5) || ($x == 8) || ($x == 11) || ($x == 14) || ($x == 17)) {
	return 2;
    } elsif(($x == 3) || ($x == 6) || ($x == 9) || ($x == 12) || ($x == 15) || ($x == 18)) {
	return 3;
    }
}

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
	if($tmp eq '.1.0') {
	    # ------------------------------------- OID_BASE.1.0	(b9stNumber)
	    if($arg eq '-n') {
		# OID_BASE.b9stIndex.x
		print "----- OID_BASE.b9stIndex.x\n" if($debug);
		&print_b9stIndex();
	    
		exit 0;
	    } else {
		&print_b9stNumber($count_counters*$count_types);

		exit 0;
	    }
	} elsif($tmp =~ /\.2\.1\.1/) {
	    # ------------------------------------- OID_BASE.2.1.1	(b9stIndex)
	    $tmp =~ s/\.2\.1\.1//; $tmp =~ s/\.//;
	    my $x;

	    if($arg eq '-n') {
		# OID_BASE.b9stIndex.x
		$x = $tmp + 1;
		
		if($x > ($count_counters*$count_types)) {
		    print "----- OID_BASE.b9stDescr.x\n" if($debug);
		    &print_b9stDescr();
		    
		    exit 0;
		}
		
		print $OID_BASE,".2.1.1.$x\n";
		print "integer\n";
		print "$x\n";
		
		exit 0;
	    } else {
		$x = $tmp;

		my $y = &y($x);
		my $z = &z($x);
		print "=> x=$x, y=$y, z=$z\n\n" if($debug);

		print $OID_BASE,".2.1.1.$x\n";
		print "integer\n";
		print "$x\n";

		exit 0;
	    }
	} elsif($tmp =~ /\.2\.1\.2/) {
	    # ------------------------------------- OID_BASE.2.1.2	(b9stDescr)
	    $tmp =~ s/\.2\.1\.2//; $tmp =~ s/\.//;
	    my $x;

	    if($arg eq '-n') {
		# OID_BASE.b9stDescr.x
		$x = $tmp + 1;
		
		if($x > ($count_counters*$count_types)) {
		    # Next is b9stValue.1
		    $x = 1;
		    
		    my $y = &y($x);
		    my $z = &z($x);
		    print "=> x=$x, y=$y, z=$z\n\n" if($debug);
		    
		    $oidval   = $x;
		    @counters = $y;
		    @types    = $z;
		} else {
		    my $y = &y($x);
		    my $z = &z($x);
		    print "=> x=$x, y=$y, z=$z\n\n" if($debug);
		    
		    print $OID_BASE,".2.1.2.$x\n";
		    print "string\n";
		    print $counters{$y},":",$types{$z},"\n";
		    
		    exit 0;
		}
	    } else {
		$x = $tmp;

		my $y = &y($x);
		my $z = &z($x);
		print "=> x=$x, y=$y, z=$z\n\n" if($debug);
		    
		print $OID_BASE,".2.1.2.$x\n";
		print "string\n";
		print $counters{$y},":",$types{$z},"\n";
		
		exit 0;
	    }
	} else {
	    # ------------------------------------- OID_BASE.2.1.3	(b9stValue)
	    $tmp =~ s/\.2\.1\.3//; $tmp =~ s/\.//;
	    my $x;

	    my ($x) = split('\.', $tmp);
	    print "=> x=$x\n" if($debug);
	    
	    if(!$x) {
		# $OID_BASE => $OID_BASE.1
		print "=> This is the top\n\n" if($debug);
		
		# OID_BASE.b9stNumber.0
		print "----- OID_BASE.b9stNumber.0\n" if($debug);
		&print_b9stNumber($count_counters*$count_types);
		
		# OID_BASE.b9stIndex.x
		print "----- OID_BASE.b9stIndex.x\n" if($debug);
		&print_b9stIndex();
		
		# OID_BASE.b9stDescr.x
		print "----- OID_BASE.b9stDescr.x\n" if($debug);
		&print_b9stDescr();
		
		print "\n" if($debug);
		
		if($arg eq '-n') {
		    $oidval   = 1;
		    @counters = qw(1);
		    @types    = qw(1);
		} else {
		    print "No value in this object - exiting!\n" if($debug);
		    exit 1;
		}
	    } elsif(($x < 1) || ($x > ($count_counters*$count_types))) {
		# || (($arg eq '-n') && (($count_counters*$count_types)+1))) {
		# Non-existant branch
		print "Non-existant branch\n" if($debug);
		exit 1;
	    } else {
		if($arg eq '-n') {
		    # $OID_BASE.x => $OID_BASE.x+1
		    $x++;
		} # else fall through...

		if($x > ($count_counters*$count_types)) {
		    print "No value in this object - exiting!\n" if($debug);
		    exit 1;
		}

		my $y = &y($x);
		my $z = &z($x);
		print "=> x=$x, y=$y, z=$z\n\n" if($debug);
		
		$oidval = $x;
		$counters[0] = $y;
		$types[0] = $z;
	    }
	}
    }
}

if($debug) {
    print "=> OID base: $OID_BASE\n";
    print "=> Counters: ";
    foreach (@counters) {
	print $_," ";
    }
    print "\n";
    print "=> Types:    ";
    foreach (@types) {
	print $_," ";
    }
    print "\n";

    exit 0;
}

# ----------

system "$rndc stats"; 

my %total; 
my %forward; 
my %reverse; 

my $tmp=$log; 
$tmp=~s/\W/_/g; 
$delta.=$tmp.".offset"; 

open(DUMP,$log) || die "$log: $!"; 

if (-e $delta) { 
    open(D,$delta) || die "can't open delta file '$delta' for '$log': $!"; 
    my $file_offset=<D>; 
    chomp $file_offset; 
    close(D); 
    my $log_size = -s $log; 
    if ($file_offset <= $log_size) { 
	seek(DUMP,$file_offset,0); 
    } 
} 

while(<DUMP>) { 
    next if /^(---|\+\+\+)/; 
    chomp; 
    my ($what, $nr, $direction) = split(/\s+/,$_,3); 
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

$oidval = 1 if(!$oidval);
my $oid = $OID_BASE.".2.1.3."; #+ .b9stTable.b9stEntry.b9stValue

foreach $nr_count (@counters) { 
    $counter  = $counters{$nr_count};

    print "\n" if($debug);
    foreach $nr_type (@types) {
	$type = $types{$nr_type};

	printf("%-9s - %-7s - ", $counter, $type) if($debug);
	if($debug) {
	    print "$oid($oidval)";
	} else {
	    print "$oid$oidval\n";
	}

	# man snmpd.conf: string, integer, unsigned, objectid, timeticks, ipaddress, counter, or gauge
	print "gauge\n" if(!$debug);

	print " -> " if($debug);
	print $DATA{$counter}{$type},"\n";

	$oidval++;
    }
} 

