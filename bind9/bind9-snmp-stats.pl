#!/usr/bin/perl -w

# {{{ $Id: bind9-snmp-stats.pl,v 1.22 2007-09-16 22:41:23 turbo Exp $
# Extract domain statistics for a Bind9 DNS server.
#
# Based on 'parse_bind9stat.pl' by
# Dobrica Pavlinusic, <dpavlin@rot13.org> 
# http://www.rot13.org/~dpavlin/sysadm.html 
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
my $CFG_FILE = "/etc/bind/.bindsnmp";
#
#   Optional arguments
#	DEBUG=4
#	DEBUG_FILE=/var/log/bind9-snmp-stats.log
#	STATS_FILE=/var/lib/named/var/log/dns-stats.log
#	IGNORE_INDEX=1
#
#   Required options
#	RNDC=/usr/sbin/rndc
#	STATS_FILE_OWNER_GROUP=bind9.bind9
#	DELTA_DIR=/var/tmp/
#
# Comments must start at the beginning of the line, and continue to the
# end of the line. The comment character is any other character than
# a-z and A-Z.
#
# NOTE1: RNDC is semi-required - if it is unset, bind9-snmp-stats.pl
#        will NOT remove the stats file after reading. This can be
#        used to load someone elses 'database' for debuging purposes
#        (using only the option 'STATS_FILE'). You'd get the exact
#        same values every time though!
#
# NOTE2: Please do NOT set the IGNORE_INDEX to anything else than 1' (or
#        better yet, leave it unset/undefined) unless I have specifically
#        asked you to enable it! Strange things WILL happen if you use this
#        the option!           !! YOU HAVE BEEN WARNED !!
#
# NOTE3: If DEBUG is specified (default is '0' - no debugging), then the
#        DEBUG_FILE is _required_!
#
# NOTE4: An environment variable with the name DEBUG_BIND9 will override
#        the DEBUG option, and make DEBUG_FILE in the config file _required_!
# }}}

# {{{ Include libraries and setup global variables
# Forces a buffer flush after every print
$|=1;

use strict; 
use BayourCOM_SNMP;

$ENV{PATH}   = "/bin:/usr/bin:/usr/sbin";

# When debugging, it's easier to type this than the full OID
# This is changed (way) below IF/WHEN we're running through SNMPd!
my $OID_BASE = "OID_BASE";
my $arg      = '';

my %DATA;    # => DATA{type}{total|reverse|forward}
my %DOMAINS; # => DOMAINS{domain}{view}{type}

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
		      "8" => "CounterFailure",
		      "9" => "CounterView"); # If this changes, update print_b9stCounterTypeView()!

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

# handle a SIGALRM - read statistics file
$SIG{'ALRM'} = \&load_information;
# }}}


# ====================================================
# =====       P R I N T  F U N C T I O N S       =====

# {{{ print_b9stNumberTotals()
sub print_b9stNumberTotals {
    my $j = shift;

    if($CFG{'DEBUG'}) {
	debug(0, "=> OID_BASE.b9stNumberTotals.0\n") if($CFG{'DEBUG'} > 1);
	debug(0, "$OID_BASE.1.0 = $count_counters\n");
    }

    if(check_val($count_counters)) {
	debug(1, "$OID_BASE.1.0\n");
	debug(1, "integer\n");
	debug(1, "$count_counters\n");
    } else {
	no_value();
    }

    debug(0, "\n") if($CFG{'DEBUG'} > 1);
}
# }}}

# {{{ print_b9stNumberDomains()
sub print_b9stNumberDomains {
    my $j = shift;

    if($CFG{'DEBUG'}) {
	debug(0, "=> OID_BASE.b9stNumberDomains.0\n") if($CFG{'DEBUG'} > 1);
	debug(0, "$OID_BASE.2.0 = $count_domains\n");
    }

    if(check_val($count_domains)) {
	debug(1, "$OID_BASE.2.0\n");
	debug(1, "integer\n");
	debug(1, "$count_domains\n");
    } else {
	no_value();
    }

    debug(0, "\n") if($CFG{'DEBUG'} > 1);
}
# }}}


# {{{ print_b9stTotalsIndex()
sub print_b9stTotalsIndex {
    my $j = shift;
    my %cnts;

    if($j) {
	debug(0, "=> OID_BASE.b9stTotalsTable.b9stTotalsEntry.b9stIndexTotals.$j\n") if($CFG{'DEBUG'} > 1);
	%cnts = ($j => $counters{$j});
    } elsif(defined($j)) {
	debug(0, "=> OID_BASE.b9stTotalsTable.b9stTotalsEntry.b9stIndexTotals.x\n") if($CFG{'DEBUG'} > 1);
	%cnts = %counters;
    } else {
	debug(0, "=> OID_BASE.b9stTotalsTable.b9stTotalsEntry.b9stIndexTotals.1\n") if($CFG{'DEBUG'} > 1);
	%cnts = ("1" => $counters{"1"});
    }

    foreach $j (keys %cnts) {
	$j =~ s/^0//;

	debug(0, "$OID_BASE.3.1.1.$j = $j\n") if($CFG{'DEBUG'});
	
	if(check_val($j)) {
	    debug(1, "$OID_BASE.3.1.1.$j\n");
	    debug(1, "integer\n");
	    debug(1, "$j\n");
	} else {
	    no_value();
	}
    }

    debug(0, "\n") if($CFG{'DEBUG'} > 1);
}
# }}}


# {{{ print_b9stCounterName()
sub print_b9stCounterName {
    my $j = shift;
    my %cnts;

    if($j) {
	debug(0, "=> OID_BASE.b9stTotalsTable.b9stTotalsEntry.b9stCounterName.$j\n") if($CFG{'DEBUG'} > 1);
	%cnts = ($j => $counters{$j});
    } elsif(defined($j)) {
	debug(0, "=> OID_BASE.b9stTotalsTable.b9stTotalsEntry.b9stCounterName.x\n") if($CFG{'DEBUG'} > 1);
	%cnts = %counters;
    } else {
	debug(0, "=> OID_BASE.b9stTotalsTable.b9stTotalsEntry.b9stCounterName.1\n") if($CFG{'DEBUG'} > 1);
	%cnts = ("1" => $counters{"1"});
    }

    foreach $j (keys %cnts) {
	debug(0, "$OID_BASE.3.1.2.$j = ".$counters{$j}."\n") if($CFG{'DEBUG'});

	if(check_val($counters{$j})) {
	    debug(1, "$OID_BASE.3.1.2.$j\n");
	    debug(1, "string\n");
	    debug(1, $counters{$j}."\n");
	} else {
	    no_value();
	}
    }

    debug(0, "\n") if($CFG{'DEBUG'} > 1);
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
	    # .3-9 => CounterType
	    $type_nr = $nr + 2;
	    last;
	}
    }

    my $type_name = ucfirst($types{$type_nr-2});
    debug(0, "=> OID_BASE.b9stTotalsTable.b9stTotalsEntry.b9stCounter$type_name.x\n") if($CFG{'DEBUG'} > 1);

    my $counter;
    foreach $nr (keys %cnts) {
	$counter  = $counters{$nr};

	debug(0, "   DATA{$counter}{$type}\n") if($CFG{'DEBUG'} >= 4);

	if($CFG{'DEBUG'}) {
	    if(defined($DATA{$counter}{$type})) {
		debug(0, "$OID_BASE.3.1.$type_nr.$nr = ".$DATA{$counter}{$type}."\n");
	    } else {
		debug(0, "$OID_BASE.3.1.$type_nr.$nr = undefined\n");
	    }
	}

	if(check_val($DATA{$counter}{$type})) {
	    debug(1, "$OID_BASE.3.1.$type_nr.$nr\n");
	    debug(1, "counter32\n");
	    debug(1, $DATA{$counter}{$type}."\n");
	} else {
	    no_value();
	}
    }

    debug(0, "\n") if($CFG{'DEBUG'} > 1);
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
    debug(0, "=> print_b9stCounterTypeDomains('$type', '$j')\n") if($CFG{'DEBUG'} > 2);

    my $nr = 0;
    my $type_nr = 0;
    foreach $nr (keys %counters) {
	if($counters{$nr} eq $type) {
	    # .1   => Index
	    # .2   => CounterName
	    # .3-9 => CounterType
	    $type_nr = $nr + 2;
	    last;
	}
    }

    my $type_name = ucfirst($counters{$type_nr-2});
    debug(0, "=> OID_BASE.b9stDomainsTable.b9stDomainsEntry.b9stCounter$type_name.x\n") if($CFG{'DEBUG'} > 1);

    my $i = 1;
    foreach my $domain (sort keys %DOMAINS) {
	foreach my $view (keys %{ $DOMAINS{$domain} }) {
	    if(($i == $j) or ($j == 0)) {
		debug(0, "$OID_BASE.4.1.$type_nr.$i = ".$DOMAINS{$domain}{$view}{$type}."\n") if($CFG{'DEBUG'});
		
		if(check_val($DOMAINS{$domain}{$view}{$type})) {
		    debug(1, "$OID_BASE.4.1.$type_nr.$i\n");
		    debug(1, "counter32\n");
		    debug(1, $DOMAINS{$domain}{$view}{$type}."\n");
		} else {
		    no_value();
		}
	    }

	    $i++;
	}
    }

    debug(0, "\n") if($CFG{'DEBUG'} > 1);
}
# }}}

# {{{ print_b9stCounterTypeView()
sub print_b9stCounterTypeView {
    my $type = shift;
    my $j    = shift;
    debug(0, "=> print_b9stCounterTypeView('$type', '$j')\n") if($CFG{'DEBUG'} > 2);

    my $type_nr = 9;
    my $type_name = "View";
    debug(0, "=> OID_BASE.b9stDomainsTable.b9stDomainsEntry.b9stCounter$type_name.x\n") if($CFG{'DEBUG'} > 1);

    my $i = 1;
    foreach my $domain (sort keys %DOMAINS) {
	foreach my $view (keys %{ $DOMAINS{$domain} }) {
	    if(($i == $j) or ($j == 0)) {
		debug(0, "$OID_BASE.4.1.$type_nr.$i = $view\n") if($CFG{'DEBUG'});
		
		if(check_val($view)) {
		    debug(1, "$OID_BASE.4.1.$type_nr.$i\n");
		    debug(1, "string\n");
		    debug(1, "$view\n");
		} else {
		    no_value();
		}
	    }

	    $i++;
	}
    }

    debug(0, "\n") if($CFG{'DEBUG'} > 1);
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

# {{{ print_b9stCounterView()
sub print_b9stCounterView {
    my $j = shift;
    &print_b9stCounterTypeView("view", $j);
}
# }}}


# {{{ print_b9stDomainsIndex()
sub print_b9stDomainsIndex {
    my $j = shift;
    my %cnts;

    if($j) {
	debug(0, "=> OID_BASE.b9stDomainsTable.b9stDomainsEntry.b9stIndexDomains.$j\n") if($CFG{'DEBUG'} > 1);
	%cnts = ($j => $DOMAINS{$j});
    } elsif(defined($j)) {
	debug(0, "=> OID_BASE.b9stDomainsTable.b9stDomainsEntry.b9stIndexDomains.x\n") if($CFG{'DEBUG'} > 1);
	%cnts = %DOMAINS;
    } else {
	debug(0, "=> OID_BASE.b9stDomainsTable.b9stDomainsEntry.b9stIndexDomains.1\n") if($CFG{'DEBUG'} > 1);
	%cnts = ("1" => $DOMAINS{"1"});
    }

    my $i = 1;
    foreach my $domain (sort keys %cnts) {
	foreach my $view (keys %{ $cnts{$domain} }) {
	    debug(0, "$OID_BASE.4.1.1.$i = $i\n") if($CFG{'DEBUG'});
	    
	    if(check_val($i)) {
		debug(1, "$OID_BASE.4.1.1.$i\n");
		debug(1, "counter32\n");
		debug(1, "$i\n");
	    } else {
		no_value();
	    }
	    
	    $i++;
	}
    }

    debug(0, "\n") if($CFG{'DEBUG'} > 1);
}
# }}}

# {{{ print_b9stDomainName()
sub print_b9stDomainName {
    my $j = shift;
    my %cnts;
    debug(0, "=> print_b9stDomainName('$j')\n") if($CFG{'DEBUG'} > 2);

    my $i = 1;
    foreach my $domain (sort keys %DOMAINS) {
	foreach my $view (keys %{ $DOMAINS{$domain} }) {
	    if(($i == $j) or ($j == 0)) {
		debug(0, "$OID_BASE.4.1.2.$i = $domain\n") if($CFG{'DEBUG'});
		
		if(check_val($domain)) {
		    debug(1, "$OID_BASE.4.1.2.$i\n");
		    debug(1, "string\n");
		    debug(1, "$domain\n");
		} else {
		    no_value();
		}
	    }

	    $i++;
	}
    }

    debug(0, "\n") if($CFG{'DEBUG'} > 1);
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
    debug(0, "=> Calling function '$func($func_arg)'\n") if($CFG{'DEBUG'} > 3);

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
    debug(0, "=> Calling function '$func($func_arg)'\n") if($CFG{'DEBUG'} > 3);

    $func = \&{$func}; # Because of 'use strict' above...
    &$func($func_arg);
}
# }}}

# {{{ Load all information needed
sub load_information {
    # Load configuration file
    %CFG = get_config($CFG_FILE);

    debug(0, "=> Dumping Bind9 stats\n") if($CFG{'RNDC'} && ($CFG{'DEBUG'} > 1));
    system($CFG{'RNDC'}." stats") if($CFG{'RNDC'});
    
    my $tmp =  $CFG{'STATS_FILE'};
    $tmp =~ s/\W/_/g;
    my $delta  =  $CFG{'DELTA_DIR'}.$tmp.".offset" if($CFG{'DELTA_DIR'});
    
    debug(0, "=> Loading statistics file '".$CFG{'STATS_FILE'}."'\n") if($CFG{'DEBUG'} > 1);
    open(DUMP, $CFG{'STATS_FILE'}) || die($CFG{'STATS_FILE'}.": $!");
    
    if(-e $delta && $CFG{'RNDC'}) {
	# Only open the delta file if RNDC is set.
	open(D, $delta) || die "can't open delta file '$delta' for '".$CFG{'STATS_FILE'}."': $!";

	debug(0, "=> Opening delta file '$delta'\n") if($CFG{'DEBUG'} > 1);
	my $file_offset = <D>;
	chomp $file_offset;
	close(D);
	my $log_size = -s $CFG{'STATS_FILE'};
	if ($file_offset <= $log_size) {
	    seek(DUMP, $file_offset, 0);
	}
    }

    # ------------- L O A D  S T A T S
    my %views;
    while(<DUMP>) {
	next if /^(---|\+\+\+)/;
	chomp;
	my ($what, $value, $domain, $view) = split(/\s+/, $_, 4);
	$view = '' if(!$view);

	if (!$domain) {
	    # TOTALS counter(s)
	    debug(0, "DATA{$what}{total} += $value\n") if($CFG{'DEBUG'} >= 4);
	    $DATA{$what}{"total"} += $value;
	} else {
	    # DOMAINS counter(s)
	    debug(0, "DOMAINS{$domain}{$view}{$what} = $value\n") if($CFG{'DEBUG'} >= 4);
	    $DOMAINS{$domain}{$view}{$what} = $value;

	    if ($domain =~ m/in-addr.arpa/) {
		debug(0, "DATA{$what}{reverse} += $value\n") if($CFG{'DEBUG'} >= 4);
		$DATA{$what}{"reverse"} += $value;
	    } else {
		debug(0, "DATA{$what}{forward} += $value\n") if($CFG{'DEBUG'} >= 4);
		$DATA{$what}{"forward"} += $value;
	    }
	}
    } 

    
    # ------------- R E C O R D  D E L T A
    if($delta && $CFG{'RNDC'}) {
	open(D,"> $delta") || die "can't open delta file '$delta' for log '".$CFG{'STATS_FILE'}."': $!"; 
	print D tell(DUMP); 
	close(D); 
    }
    
    close(DUMP); 

    if($CFG{'RNDC'}) {
	# Only remove the stats and delta file if RNDC is set!
	unlink($CFG{'STATS_FILE'});
	system("touch ".$CFG{'STATS_FILE'});

	unlink($delta);
	system("chown ".$CFG{'STATS_FILE_OWNER_GROUP'}." ".$CFG{'STATS_FILE'});
    }

    # ------------- C O U N T  D O M A I N S
    if($CFG{'DEBUG'} >= 4) {
	debug(0, "\n");
	debug(0, "=> Going through and counting domains.\n");
    }
    my %tmp1;
    foreach my $domain (sort keys %DOMAINS) {
	if(!$tmp1{$domain}) {
	    $count_domains++;
	    $tmp1{$domain} = $domain;
	}
    }
    
    # Schedule an alarm once every five minutes to re-read information.
    alarm(5*60);

    debug(0, "\n") if($CFG{'DEBUG'} > 1);
}
# }}}

# ====================================================
# =====          P R O C E S S  A R G S          =====

# {{{ Go through the argument(s) passed to the program
my $ALL = 0;
for(my $i=0; $ARGV[$i]; $i++) {
    if($ARGV[$i] eq '--help' || $ARGV[$i] eq '-h' || $ARGV[$i] eq '?' ) {
	help();
	exit 1;
    } elsif($ARGV[$i] eq '--all' || $ARGV[$i] eq '-a') {
	$ALL = 1;
    } else {
	print "Unknown option '",$ARGV[$i],"'\n";
	help();
	exit 1;
    }
}
# }}}

# Load information
&load_information();

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
    # ALWAYS override the OID_BASE value since we're
    # running through the SNMP daemon!
    $OID_BASE = ".1.3.6.1.4.1.8767.2.1";

    while(<>) {
	if (m!^PING!){
	    print "PONG\n";
	    next;
	}

	# Re-get the DEBUG config option (so that we don't have to restart process).
	$CFG{'DEBUG'} = get_config($CFG_FILE, 'DEBUG');
	
	# {{{ Get all run arguments - next/specfic OID
	my $arg = $_; chomp($arg);
	debug(0, "=> ARG=$arg\n") if($CFG{'DEBUG'} > 2);
	
	# Get next line from STDIN -> OID number.
	# $arg == 'getnext' => Get next OID
	# $arg == 'get' (?) => Get specified OID
	$oid = <>; chomp($oid);
	$oid =~ s/$OID_BASE//; # Remove the OID base
	$oid =~ s/OID_BASE//;  # Remove the OID base (if we're debugging)
	$oid =~ s/^\.//;       # Remove the first dot if it exists - it's in the way!
	debug(0, "=> OID=$OID_BASE.$oid\n") if($CFG{'DEBUG'} > 2);
	
	my @tmp = split('\.', $oid);
	output_extra_debugging(@tmp) if($CFG{'DEBUG'} > 2);
	
	debug(0, "=> count_counters=$count_counters, count_types=$count_types, count_domains=$count_domains\n") if($CFG{'DEBUG'} > 2);
# }}} Get arguments
	
	if(!defined($tmp[0])) {
	    # {{{ ------------------------------------- OID_BASE                                    
	    if($arg eq 'getnext') {
		&print_b9stNumberTotals(0);
	    } else {
		no_value(); next;
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
		    no_value(); next;
		}
	    }
# }}} # OID_BASE.1

	} elsif($tmp[0] == 2) {
	    # {{{ ------------------------------------- OID_BASE.2		(b9stNumberDomains) 
	    if($arg eq 'getnext') {
		if(!defined($tmp[1])) {
		    &print_b9stNumberDomains(0);
		} else {
		    if($CFG{'IGNORE_INDEX'}) {
			&call_func_total(2, 1);
		    } else {
			&call_func_total(1, 1);
		    }
		}
	    } else {
		if(defined($tmp[1])) {
		    &print_b9stNumberDomains(0);
		} else {
		    no_value(); next;
		}
	    }
# }}} # OID_BASE.2

	} elsif($tmp[0] == 3) {
	    # {{{ ------------------------------------- OID_BASE.3		(b9stTotalsTable)   
	    if($arg eq 'getnext') {
		# {{{ CMD: getnext
		# Make sure to skip the OID_BASE.3.1.1 branch - it's the index and should not be returned!
		if(!$tmp[2] && !$tmp[3]) {
		    if($CFG{'IGNORE_INDEX'}) {
			&call_func_total(2, 1);
		    } else {
			&call_func_total(1, 1);
		    }
		} elsif(!$tmp[3]) {
		    if(($tmp[2] == 1) && $CFG{'IGNORE_INDEX'}) {
			&call_func_total(2, 1);
		    } elsif($tmp[2] < $count_counters) {
			debug(0, "tmp[2] < $count_counters\n") if($CFG{'DEBUG'});
			if($tmp[2] > 1) {
			    debug(0, "tmp[2] > 1\n") if($CFG{'DEBUG'});
			    &call_func_total($tmp[2], 1);
			} else {
			    debug(0, "tmp[2] < 1\n") if($CFG{'DEBUG'});
			    if($CFG{'IGNORE_INDEX'}) {
				&call_func_total($tmp[2]+1, 1);
				#no_value("index");
			    } else {
				&call_func_total($tmp[2], 1);
			    }
			}
		    } else {
			&call_func_domain(2, 1);
		    }
		} else {
		    my $x = $tmp[3] + 1;
		    
		    if($x > $count_counters) {
			debug(0, "=> x > count_counters ($x > $count_counters)\n") if($CFG{'DEBUG'} > 2);
			if(($tmp[2] == 1) && $CFG{'IGNORE_INDEX'}) {
			    &call_func_total($tmp[2]+1, 1);
			    #no_value("index");
			} else {
			    if($prints_total{$tmp[2]+1}) {
				&call_func_total($tmp[2]+1, 1);
			    } else {
				&call_func_domain(2, 1);
			    }
			}
		    } else {
			if(($tmp[2] == 1) && $CFG{'IGNORE_INDEX'}) {
			    &call_func_total($tmp[2]+1, 1);
			    #no_value("index");
			} else {
			    debug(0, "=> !($x > $count_counters) => call_func_total(".$tmp[2].", ".($tmp[3]+1).")\n") if($CFG{'DEBUG'} > 2);
			    &call_func_total($tmp[2], $tmp[3]+1);
			}
		    }
		}
# }}} # CMD: getnext
	    } else {
		# {{{ CMD: get
		if(!$tmp[3] || (($tmp[2] == 1) && $CFG{'IGNORE_INDEX'})) {
		    no_value();
		} elsif($tmp[2] && $prints_total{$tmp[2]}) {
		    debug(0, "tmp[2] && prints_total{tmp[2]} (".$prints_total{$tmp[2]}.")\n") if($CFG{'DEBUG'});
		    if(($tmp[2] == 1) && $CFG{'IGNORE_INDEX'}) {
			no_value("index");
		    } else {
			&call_func_total($tmp[2], $tmp[3]);
		    }
		} elsif($tmp[2] && $prints_domain{$tmp[2]}) {
		    &call_func_domain($tmp[2], $tmp[3]);
		} else {
		    # End of MIB.
		    no_value();
		}
# }}} # CMD: get
	    }
# }}} # OID_BASE.3

	} elsif($tmp[0] == 4) {
	    # {{{ ------------------------------------- OID_BASE.4		(b9stDomainsTable)  
	    if($arg eq 'getnext') {
		# {{{ CMD: getnext
		# Make sure to skip the OID_BASE.4.1.1 branch - it's the index and should not be returned!
		if(!$tmp[2] && !$tmp[3]) {
		    if($CFG{'IGNORE_INDEX'}) {
			&call_func_domain(2, 1);
		    } else {
			&call_func_domain(1, 1);
		    }
		} elsif(!$tmp[3]) {
		    if(($tmp[2] == 1) && $CFG{'IGNORE_INDEX'}) {
			&call_func_domain(2, 1);
		    } else {
			&call_func_domain($tmp[2], 1);
		    }
		} else {
		    my $x = $tmp[3] + 1;
		    
		    if($x > $count_domains) {
			if($prints_domain{$tmp[2]+1}) {
			    &call_func_domain($tmp[2]+1, 1);
			} else {
			    # End of MIB.
			    no_value();
			}
		    } else {
			if(($tmp[2] == 1) && $CFG{'IGNORE_INDEX'}) {
			    no_value("index");
			} else {
			    debug(0, "=> $x < $count_domains\n") if($CFG{'DEBUG'} > 2);
			    &call_func_domain($tmp[2], $tmp[3]+1);
			}
		    }
		}
# }}} # CMD: getnext
	    } else {
		# {{{ CMD: get
		if($tmp[2] && $prints_domain{$tmp[2]}) {
		    if(($tmp[2] == 1) && $CFG{'IGNORE_INDEX'}) {
			no_value();
		    } else {
			&call_func_domain($tmp[2], $tmp[3]);
		    }
		} else {
		    no_value();
		}
# }}} # CMD: get
	    }
# }}} # OID_BASE.4

	} else {
	    # {{{ ------------------------------------- OID_BASE.?              (Unknown OID)       
	    no_value();
# }}}
	}
    }
# }}} # Go through commands
}
