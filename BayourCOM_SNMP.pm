# {{{ $Id: BayourCOM_SNMP.pm,v 1.3 2006-02-05 18:45:37 turbo Exp $
# Common functions used by Bayour.COM SNMP modules.
#
# Copyright 2005 Turbo Fredriksson <turbo@bayour.com>.
# This software is distributed under GPL v2.
# }}}
package BayourCOM_SNMP;
use POSIX qw(strftime);

# ----- INTERNAL

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
    die("DEBUG_FILE not set in config file!\n") if(!$main::CFG{'DEBUG_FILE'});

    if(!open(LOG, ">> ".$main::CFG{'DEBUG_FILE'})) {
	&echo(0, "Can't open logfile '".$main::CFG{'DEBUG_FILE'}."', $!\n") if($main::CFG{'DEBUG'});
	return 0;
    } else {
	return 1;
    }
}
# }}}

# ----- EXTERNAL

# {{{ Show usage
sub help {
    my $name = `basename $0`; chomp($name);

    &echo(0, "Usage: $name [option] [oid]\n");
    &echo(0, "Options: --debug|-d	Run in debug mode\n");
    &echo(0, "         --all|-a	Get all information\n");
    &echo(0, "         -n		Get next OID ('oid' required)\n");
    &echo(0, "         -g		Get specified OID ('oid' required)\n");

    exit 1 if($main::CFG{'DEBUG'});
}
# }}}

# {{{ Log output
sub echo {
    my $stdout = shift;
    my $string = shift;
    my $log_opened = 0;

    # Open logfile if debugging OR running from snmpd.
    if($main::CFG{'DEBUG'}) {
	if(&open_log()) {
	    $log_opened = 1;
	    open(STDERR, ">&LOG") if(($main::CFG{'DEBUG'} <= 2) || $ENV{'MIBDIRS'});
	}
    }

    if($stdout) {
	print $string;
    } elsif($log_opened) {
	print LOG &get_timestring()," " if($main::CFG{'DEBUG'} > 2);
	print LOG $string;
    }
}
# }}}

# {{{ Return 'no such value'
sub no_value {
    &echo(0, "=> No value in this object - exiting!\n") if($main::CFG{'DEBUG'} > 1);
    
    &echo(1, "NONE\n");
    &echo(0, "\n") if($main::CFG{'DEBUG'} > 1);
}
# }}}

# {{{ Load configuration file
sub get_config {
    my $cfg_file = shift;
    my $option = shift;
    my($line, $key, $value);
    my(%CFG);

    $option = 0 if(!defined($option));

    if(-e $cfg_file) {
	open(CFG, "< ".$cfg_file) || die("Can't open $cfg_file, $!\n");
	while(!eof(CFG)) {
	    $line = <CFG>; chomp($line);
	    next if($line !~ /^[A-Z]/);

	    ($key, $value) = split('=', $line);

	    if(!$option) {
		# Get all options
		$CFG{$key} = $value;
	    } elsif($option eq $key) {
		# Get only this option
		$CFG{$key} = $value;
	    }
	}
	close(CFG);
    }

    $CFG{'DEBUG'} = 0  if(!defined($CFG{'DEBUG'}));
    $CFG{'IGNORE_INDEX'} = 1 if(!defined($CFG{'IGNORE_INDEX'}));

    # A debug value from the environment overrides!
    $CFG{'DEBUG'} = $ENV{'DEBUG_BIND9'} if(defined($ENV{'DEBUG_BIND9'}));

    return(%CFG);
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

    BayourCOM_SNMP::echo(0, $string);
}
# }}} # Extra debugging

1;
__END__
