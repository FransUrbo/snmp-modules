#!/usr/bin/perl -w

# {{{ $Id: bind9-snmp-stats.pl,v 1.11 2005-11-05 11:33:28 turbo Exp $
# Extract domain statistics for a Bind9 DNS server.
#
# Based on 'parse_bind9stat.pl' by
# Dobrica Pavlinusic, <dpavlin@rot13.org> 
# http://www.rot13.org/~dpavlin/sysadm.html 
#
# Copyright 2005 Turbo Fredriksson <turbo@bayour.com>.
# This software is distributed under GPL v2.
# }}}

# {{{ Include libraries and setup global variables
# Forces a buffer flush after every print
$|=1;

use strict; 
use POSIX qw(strftime);

$ENV{PATH}   = "/bin:/usr/bin:/usr/sbin";

my $OID_BASE;
$OID_BASE = "OID_BASE"; # When debugging, it's easier to type this than the full OID
if($ENV{'MIBDIRS'}) {
    # ALWAYS override this if we're running through the SNMP daemon!
    $OID_BASE = ".1.3.6.1.4.1.8767.2.1"; # .iso.org.dod.internet.private.enterprises.bayourcom.snmp.bind9stats
}

my $log      = "/var/lib/named/var/log/dns-stats.log";
my $rndc     = "/usr/sbin/rndc"; 
my $delta    = "/var/tmp/"; 

my $DEBUG    = 4;
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

# The total numbers
my(%total, %forward, %reverse);

# The input OID
my($oid);

# handle a SIGALRM - read information from the SQL server
$SIG{'ALRM'} = \&load_information;
# }}}


# ====================================================
# =====       P R I N T  F U N C T I O N S       =====

# {{{ print_b9stNumberTotals()
sub print_b9stNumberTotals {
    my $j = shift;

    if($DEBUG) {
	&echo(0, "=> OID_BASE.b9stNumberTotals.0\n") if($DEBUG > 1);
	&echo(0, "$OID_BASE.1.0 = $count_counters\n");
    }

    &echo(1, "$OID_BASE.1.0\n");
    &echo(1, "integer\n");
    &echo(1, "$count_counters\n");

    &echo(0, "\n") if($DEBUG > 1);
}
# }}}

# {{{ print_b9stNumberDomains()
sub print_b9stNumberDomains {
    my $j = shift;

    if($DEBUG) {
	&echo(0, "=> OID_BASE.b9stNumberDomains.0\n") if($DEBUG > 1);
	&echo(0, "$OID_BASE.2.0 = $count_domains\n");
    }

    &echo(1, "$OID_BASE.2.0\n");
    &echo(1, "integer\n");
    &echo(1, "$count_domains\n");

    &echo(0, "\n") if($DEBUG > 1);
}
# }}}


# {{{ print_b9stTotalsIndex()
sub print_b9stTotalsIndex {
    my $j = shift;
    my %cnts;

    if($j) {
	&echo(0, "=> OID_BASE.b9stTotalsTable.b9stIndexTotals.$j\n") if($DEBUG > 1);
	%cnts = ($j => $counters{$j});
    } elsif(defined($j)) {
	&echo(0, "=> OID_BASE.b9stTotalsTable.b9stIndexTotals.x\n") if($DEBUG > 1);
	%cnts = %counters;
    } else {
	&echo(0, "=> OID_BASE.b9stTotalsTable.b9stIndexTotals.1\n") if($DEBUG > 1);
	%cnts = ("1" => $counters{"1"});
    }

    foreach $j (keys %cnts) {
	$j =~ s/^0//;
	&echo(0, "$OID_BASE.3.1.1.$j = $j\n") if($DEBUG);
	
	&echo(1, "$OID_BASE.3.1.1.$j\n");
	&echo(1, "integer\n");
	&echo(1, "$j\n");
    }

    &echo(0, "\n") if($DEBUG > 1);
}
# }}}


# {{{ print_b9stCounterName()
sub print_b9stCounterName {
    my $j = shift;
    my %cnts;

    if($j) {
	&echo(0, "=> OID_BASE.b9stTotalsTable.b9stCounterName.$j\n") if($DEBUG > 1);
	%cnts = ($j => $counters{$j});
    } elsif(defined($j)) {
	&echo(0, "=> OID_BASE.b9stTotalsTable.b9stCounterName.x\n") if($DEBUG > 1);
	%cnts = %counters;
    } else {
	&echo(0, "=> OID_BASE.b9stTotalsTable.b9stCounterName.1\n") if($DEBUG > 1);
	%cnts = ("1" => $counters{"1"});
    }

    foreach $j (keys %cnts) {
	&echo(0, "$OID_BASE.3.1.2.$j = ".$counters{$j}."\n") if($DEBUG);

	&echo(1, "$OID_BASE.3.1.2.$j\n");
	&echo(1, "string\n");
	&echo(1, $counters{$j}."\n");
    }

    &echo(0, "\n") if($DEBUG > 1);
}
# }}}

# {{{ print_b9stCounterTypeTotal()
sub print_b9stCounterTypeTotal {
    my $type = shift;
    my $j    = shift;

    my %cnts;
    if($j) {
	%cnts = ($j => $counters{$j});
    } elsif(defined($j)) {
	%cnts = %counters;
    } else {
	%cnts = ("1" => $counters{"1"});
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
    &echo(0, "=> OID_BASE.b9stTotalsTable.b9stCounter$type_name.x\n") if($DEBUG > 1);

    my $counter;
    foreach $nr (keys %cnts) {
	$counter  = $counters{$nr};

	&echo(0, "$OID_BASE.3.1.$type_nr.$nr = ".$DATA{$counter}{$type}."\n") if($DEBUG);

	&echo(1, "$OID_BASE.3.1.$type_nr.$nr\n");
	&echo(1, "integer\n");
	&echo(1, $DATA{$counter}{$type}."\n");
    }

    &echo(0, "\n") if($DEBUG > 1);
}
# }}}

# {{{ print_b9stCounterTotal()
sub print_b9stCounterTotal {
    my $j = shift;
    &print_b9stCounterTypeTotal("total", $j);
}
# }}}

# {{{ print_b9stCounterForward()
sub print_b9stCounterForward {
    my $j = shift;
    &print_b9stCounterTypeTotal("forward", $j);
}
# }}}

# {{{ print_b9stCounterReverse()
sub print_b9stCounterReverse {
    my $j = shift;
    &print_b9stCounterTypeTotal("reverse", $j);
}
# }}}

# {{{ print_b9stCounterTypeDomains()
sub print_b9stCounterTypeDomains {
    my $type = shift;
    my $j    = shift;

    my %cnts;
    if($j) {
	my $i = $j;
	$j = sprintf("%02d", $j);

	%cnts = ($i => $DOMAINS{$j});
    } elsif(defined($j)) {
	%cnts = %DOMAINS;
    } else {
	%cnts = ("1" => $DOMAINS{"1"});
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
    &echo(0, "=> OID_BASE.b9stDomainsTable.b9stCounter$type_name.x\n") if($DEBUG > 1);

    foreach my $i (sort keys %cnts) {
	my ($domain, $value) = split(':', $cnts{$i}{$type});

	$i =~ s/^0//;
	&echo(0, "$OID_BASE.4.1.$type_nr.$i = $value\n") if($DEBUG);

	&echo(1, "$OID_BASE.4.1.$type_nr.$i\n");
	&echo(1, "integer\n");
	&echo(1, "$value\n");
    }

    &echo(0, "\n") if($DEBUG > 1);
}
# }}}

# {{{ print_b9stCounterSuccess()
sub print_b9stCounterSuccess {
    my $j = shift;
    &print_b9stCounterTypeDomains("success", $j);
}
# }}}

# {{{ print_b9stCounterReferral()
sub print_b9stCounterReferral {
    my $j = shift;
    &print_b9stCounterTypeDomains("referral", $j);
}
# }}}

# {{{ print_b9stCounterNXRRSet()
sub print_b9stCounterNXRRSet {
    my $j = shift;
    &print_b9stCounterTypeDomains("nxrrset", $j);
}
# }}}

# {{{ print_b9stCounterNXDomain()
sub print_b9stCounterNXDomain {
    my $j = shift;
    &print_b9stCounterTypeDomains("nxdomain", $j);
}
# }}}

# {{{ print_b9stCounterRecursion()
sub print_b9stCounterRecursion {
    my $j = shift;
    &print_b9stCounterTypeDomains("recursion", $j);
}
# }}}

# {{{ print_b9stCounterFailure()
sub print_b9stCounterFailure {
    my $j = shift;
    &print_b9stCounterTypeDomains("failure", $j);
}
# }}}


# {{{ print_b9stDomainsIndex()
sub print_b9stDomainsIndex {
    my $j = shift;
    my %cnts;

    if($j) {
	&echo(0, "=> OID_BASE.b9stDomainsTable.b9stIndexDomains.$j\n") if($DEBUG > 1);
	%cnts = ($j => $DOMAINS{$j});
    } elsif(defined($j)) {
	&echo(0, "=> OID_BASE.b9stDomainsTable.b9stIndexDomains.x\n") if($DEBUG > 1);
	%cnts = %DOMAINS;
    } else {
	&echo(0, "=> OID_BASE.b9stDomainsTable.b9stIndexDomains.1\n") if($DEBUG > 1);
	%cnts = ("1" => $DOMAINS{"1"});
    }

    foreach $j (sort keys %cnts) {
	$j =~ s/^0//;
	&echo(0, "$OID_BASE.4.1.1.$j = $j\n") if($DEBUG);

	&echo(1, "$OID_BASE.4.1.1.$j\n");
	&echo(1, "integer\n");
	&echo(1, "$j\n");
    }

    &echo(0, "\n") if($DEBUG > 1);
}
# }}}

# {{{ print_b9stDomainName()
sub print_b9stDomainName {
    my $j = shift;
    my %cnts;

    if($j) {
	&echo(0, "=> OID_BASE.b9stDomainsTable.b9stDomainName.$j\n") if($DEBUG > 1);

	my $i = $j;
	$j = sprintf("%02d", $j);

	%cnts = ($j => $DOMAINS{$j});
    } elsif(defined($j)) {
	&echo(0, "=> OID_BASE.b9stDomainsTable.b9stDomainName.x\n") if($DEBUG > 1);
	%cnts = %DOMAINS;
    } else {
	&echo(0, "=> OID_BASE.b9stDomainsTable.b9stDomainName.1\n") if($DEBUG > 1);
	%cnts = ("1" => $DOMAINS{"1"});
    }

    foreach my $j (sort keys %cnts) {
	my $domain = (split(':', $cnts{$j}{"success"}))[0];

	$j =~ s/^0//;
	&echo(0, "$OID_BASE.4.1.2.$j = $domain\n") if($DEBUG);

	&echo(1, "$OID_BASE.4.1.2.$j\n");
	&echo(1, "string\n");
	&echo(1, "$domain\n");
    }

    &echo(0, "\n") if($DEBUG > 1);
}
# }}}


# ====================================================
# =====        M I S C  F U N C T I O N S        =====

# {{{ call_func_total()
sub call_func_total {
    my $func_nr  = shift;
    my $func_arg = shift;
    
    my $func = "print_b9st".$prints_total{$func_nr};
    $func_arg = '' if(!defined($func_arg));
    &echo(0, "=> Calling function '$func($func_arg)'\n") if($DEBUG > 3);

    $func = \&{$func}; # Because of 'use strict' above...
    &$func($func_arg);
}
# }}}

# {{{ call_func_domain()
sub call_func_domain {
    my $func_nr  = shift;
    my $func_arg = shift;
    
    my $func = "print_b9st".$prints_domain{$func_nr};
    $func_arg = '' if(!defined($func_arg));
    &echo(0, "=> Calling function '$func($func_arg)'\n") if($DEBUG > 3);

    $func = \&{$func}; # Because of 'use strict' above...
    &$func($func_arg);
}
# }}}


# {{{ Output some extra debugging
sub output_extra_debugging {
    my @tmp = @_;

    my $string = "=> ";
    for(my $i=0; defined($tmp[$i]); $i++) {
	$string .= "tmp[$i]=".$tmp[$i];
	$string .= ", " if(defined($tmp[$i+1]));
    }
    $string .= "\n";

    &echo(0, $string);
}
# }}} # Extra debugging

# {{{ Find the current date and time
# Returns a string something like: '10/8-96 16:27'
sub get_timestring {
    my($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime;

    return POSIX::strftime("20%y-%m-%d %H:%M:%S",
			    $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst);
}
# }}}

# {{{ Open logfile for debugging
sub open_log {
    if(!open(LOG, ">> /var/log/bind9-snmp-stats.log")) {
	&echo(0, "Can't open logfile '/var/log/bind9-snmp-stats.log', $!\n") if($DEBUG);
	return 0;
    } else {
	return 1;
    }
}
# }}}

# {{{ Log output
sub echo {
    my $stdout = shift;
    my $string = shift;
    my $log_opened = 0;

    # Open logfile if debugging OR running from snmpd.
    if($DEBUG) {
	if(&open_log()) {
	    $log_opened = 1;
	    open(STDERR, ">&LOG") if(($DEBUG <= 2) || $ENV{'MIBDIRS'});
	}
    }

    if($stdout) {
	print $string;
    } elsif($log_opened) {
	print LOG &get_timestring()," " if($DEBUG > 2);
	print LOG $string;
    }
}
# }}}

# {{{ Return 'no such value'
sub no_value {
    my $reason = shift;

    $reason = " $reason" if(defined($reason));

    &echo(0, "=> No value in this object$reason - exiting!\n") if($DEBUG > 1);
    
    &echo(1, "NONE\n");
    &echo(0, "\n") if($DEBUG > 1);
}
# }}}

# {{{ Load all information needed
sub load_information {
    system "$rndc stats" if($rndc);
    
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
		my $cnt  = sprintf("%02d", $count_domains);
		
		$tmp2{$cnt}{$what} = $domain.":".$DOMAINS{$domain}{$what};
	    }
	}
    }
    $count_domains -= 1;
    
    undef(%DOMAINS);
    %DOMAINS = %tmp2;

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
	&help();
    } elsif($ARGV[$i] eq '--debug' || $ARGV[$i] eq '-d') {
	$DEBUG++;
    } elsif($ARGV[$i] eq '--all' || $ARGV[$i] eq '-a') {
	$ALL = 1;
    }
}
# }}}

if($ALL) {
    # {{{ Output the whole MIB tree - used mainly/only for debugging purposes
    &print_b9stNumberTotals(0);
    &print_b9stNumberDomains(0);
    
    foreach my $j (keys %prints_total) {
	&call_func_total($j, 0);
    }
    
    foreach my $j (keys %prints_domain) {
	&call_func_domain($j, 0);
    }
# }}} 
} else {
    # {{{ Go through the commands sent on STDIN
    while(<>) {
	if (m!^PING!){
	    print "PONG\n";
	    next;
	}
	
	# {{{ Get all run arguments - next/specfic OID
	my $arg = $_; chomp($arg);
	&echo(0, "=> ARG=$arg\n") if($DEBUG > 2);
	
	# Get next line from STDIN -> OID number.
	# $arg == 'getnext' => Get next OID
	# $arg == 'get' (?) => Get specified OID
	$oid = <>; chomp($oid);
	$oid =~ s/$OID_BASE//; # Remove the OID base
	$oid =~ s/OID_BASE//;  # Remove the OID base (if we're debugging)
	$oid =~ s/^\.//;       # Remove the first dot if it exists - it's in the way!
	&echo(0, "=> OID=$OID_BASE.$oid\n") if($DEBUG > 2);
	
	my @tmp = split('\.', $oid);
	&output_extra_debugging(@tmp) if($DEBUG > 2);
	
	&echo(0, "=> count_counters=$count_counters, count_types=$count_types, count_domains=$count_domains\n") if($DEBUG > 2);
# }}} Get arguments
	
	if(!defined($tmp[0])) {
	    # {{{ ------------------------------------- OID_BASE                                    
	    if($arg eq 'getnext') {
		&print_b9stNumberTotals(0);
	    } else {
		&no_value(); next;
	    }
# }}} # OID_BASE

	} elsif($tmp[0] == 1) {
	    # {{{ ------------------------------------- OID_BASE.1		(b9stNumberTotals)  
	    if($arg eq 'getnext') {
		if(!defined($tmp[1])) {
		    &print_b9stNumberTotals(0);
		} else {
		    &print_b9stNumberDomains(0);
		}
	    } elsif($arg eq 'get') {
		if(defined($tmp[1])) {
		    &print_b9stNumberTotals(0);
		} else {
		    &no_value(); next;
		}
	    }
# }}} # OID_BASE.1

	} elsif($tmp[0] == 2) {
	    # {{{ ------------------------------------- OID_BASE.2		(b9stNumberDomains) 
	    if($arg eq 'getnext') {
		if(!defined($tmp[1])) {
		    &print_b9stNumberDomains(0);
		} else {
		    &call_func_total(1, 1);
		}
	    } else {
		if(defined($tmp[1])) {
		    &print_b9stNumberDomains(0);
		} else {
		    &no_value(); next;
		}
	    }
# }}} # OID_BASE.2

	} elsif($tmp[0] == 3) {
	    # {{{ ------------------------------------- OID_BASE.3		(b9stTotalsTable)   
	    if($arg eq 'getnext') {
		# Make sure to skip the OID_BASE.3.1.1 branch - it's the index and should not be returned!
		if(!$tmp[2] && !$tmp[3]) {
		    &call_func_total(2, 1);
		} elsif(!$tmp[3]) {
		    if($tmp[2] < $count_counters) {
			&echo(0, "tmp[2] < $count_counters\n");
			if($tmp[2] > 1) {
			    &echo(0, "tmp[2] > 1\n");
			    &call_func_total($tmp[2], 1);
			} else {
			    &echo(0, "tmp[2] < 1\n");
			    &no_value("(Index)");
			}
		    } else {
			&call_func_domain(2, 1);
		    }
		} else {
		    my $x = $tmp[3] + 1;
		    
		    if($x > $count_counters) {
			&echo(0, "=> x > count_counters ($x > $count_counters)\n") if($DEBUG > 2);
			if($tmp[2] == 1) {
			    &no_value("(Index)");
			} else {
			    if($prints_total{$tmp[2]+1}) {
				&call_func_total($tmp[2]+1, 1);
			    } else {
				&call_func_domain(2, 1);
			    }
			}
		    } else {
			if($tmp[2] == 1) {
			    &no_value("(Index)");
			} else {
			    &echo(0, "=> !($x > $count_counters) => call_func_total(".$tmp[2].", ".($tmp[3]+1).")\n") if($DEBUG > 2);
			    &call_func_total($tmp[2], $tmp[3]+1);
			}
		    }
		}
	    } else {
		if(!$tmp[3] || ($tmp[2] == 1)) {
		    &no_value();
		} elsif($tmp[2] && $prints_total{$tmp[2]}) {
		    &echo(0, "tmp[2] && prints_total{tmp[2]} (".$prints_total{$tmp[2]}.")\n");
		    if($tmp[2] > 1) {
			&no_value("(Index)");
		    } else {
			&call_func_total($tmp[2]+1, $tmp[3]);
		    }
		} elsif($tmp[2] && $prints_domain{$tmp[2]}) {
		    &call_func_domain($tmp[2], $tmp[3]);
		} else {
		    # End of MIB.
		    &no_value();
		}
	    }
# }}} # OID_BASE.3

	} elsif($tmp[0] == 4) {
	    # {{{ ------------------------------------- OID_BASE.4		(b9stDomainsTable)  
	    if($arg eq 'getnext') {
		# Make sure to skip the OID_BASE.4.1.1 branch - it's the index and should not be returned!
		if(!$tmp[2] && !$tmp[3]) {
		    &call_func_domain(2, 1);
		} elsif(!$tmp[3]) {
		    if($tmp[2] > 1) {
			&call_func_domain($tmp[2], 1);
		    } else {
			&call_func_domain($tmp[2]+1, 1);
		    }
		} else {
		    my $x = $tmp[3] + 1;
		    
		    if($x > $count_domains) {
			if($prints_domain{$tmp[2]+1}) {
			    &call_func_domain($tmp[2]+1, 1);
			} else {
			    # End of MIB.
			    &no_value();
			}
		    } else {
			if($tmp[2] == 1) {
			    &no_value("(Index)");
			} else {
			    &echo(0, "=> $x < $count_domains\n") if($DEBUG > 2);
			    &call_func_domain($tmp[2], $tmp[3]+1);
			}
		    }
		}
	    } else {
		if($tmp[2] && $prints_domain{$tmp[2]}) {
		    &call_func_domain($tmp[2], $tmp[3]);
		} else {
		    &no_value();
		}
	    }
# }}} # OID_BASE.4

	} else {
	    # {{{ ------------------------------------- OID_BASE.?              (Unknown OID)       
	    &no_value();
# }}}
	}
    }
# }}} # Go through commands
}
