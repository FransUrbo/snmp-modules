#!/usr/bin/perl -w

use strict;
my %pool_status = ('DEGRADED'	=> 1,
		   'FAULTED'	=> 2,
		   'OFFLINE'	=> 3,
		   'ONLINE'	=> 4,
		   'REMOVED'	=> 5,
		   'UNAVAIL'	=> 6);
my(%CFG, %STATUS);
$CFG{'ZPOOL'} = "zpool";

# ========================================

sub zpool_get_status {
    my($pool, $state, $vdev);

    open(ZPOOL, "$CFG{'ZPOOL'} status |") ||
	die("Can't call zpool, $!");
    while(! eof(ZPOOL)) {
	my $zpool = <ZPOOL>;
	chomp($zpool);

	next if ($zpool =~ /^$/ || $zpool =~ /^errors: /);

	if ($zpool =~ /^  pool: /) {
	    $pool =  $zpool;
	    $pool =~ s/.* //;

	    # Start from scratch - start of a pool status
	    undef($state);
	    undef($vdev);

	    next;
	} elsif ($zpool =~ /^ state: /) {
	    $state =  $zpool;
	    $state =~ s/.* //;

	    # Skip to the interesting bit (first VDEV)
	    while (! eof(ZPOOL)) {
		$zpool = <ZPOOL>;

		if ($zpool =~ /NAME.*STATE.*READ.*WRITE.*CKSUM/) {
		    last;
		}
	    }
	} elsif ($zpool =~ /raid|mirror/) {
	    $zpool =~ s/^	//; # Remove initial tab to get something to split on
	    $vdev = (split(' ', $zpool))[0];

	    # Get next line - the dev
	    $zpool = <ZPOOL>;
	    chomp($zpool);
	} elsif ($zpool =~ /spares|cache/) {
	    # For spares and caches - ignore. They aren't online, so no read/write/cksum values
	    undef($vdev); # Don't reuse the previous vdev value.
	    next;
	}

	if ($zpool && $state && $vdev) {
	    $zpool =~ s/^	//; # Remove initial tab to get something to split on
	    my $dev = (split(' ', $zpool))[0];

#	    print "=> {$pool}{$vdev}{$dev} = '$zpool'\n";

	    ($STATUS{$pool}{$vdev}{$dev}{'dev'}, $STATUS{$pool}{$vdev}{$dev}{'state'},
	     $STATUS{$pool}{$vdev}{$dev}{'read'}, $STATUS{$pool}{$vdev}{$dev}{'write'},
	     $STATUS{$pool}{$vdev}{$dev}{'cksum'}) = split(' ', $zpool);

	    # Translate the status to a number according to %pool_status
	    foreach my $stat (keys %pool_status) {
		if ($STATUS{$pool}{$vdev}{$dev}{'state'} eq $stat) {
		    $STATUS{$pool}{$vdev}{$dev}{'state'} = $pool_status{$stat};
		}
	    }

#	    printf("  %s\t%s\t%s\t%s\t%s\n", 
#		   $STATUS{$pool}{$vdev}{$dev}{'dev'}, $STATUS{$pool}{$vdev}{$dev}{'state'},
#		   $STATUS{$pool}{$vdev}{$dev}{'read'}, $STATUS{$pool}{$vdev}{$dev}{'write'},
#		   $STATUS{$pool}{$vdev}{$dev}{'cksum'});
	}
    }

    close(ZPOOL);
}

# ========================================

&zpool_get_status();
foreach my $pool (keys %STATUS) {
    print "$pool\n";
    foreach my $vdev (keys %{$STATUS{$pool}}) {
	print "  $vdev\n";
	foreach my $dev (keys %{$STATUS{$pool}{$vdev}}) {
	    print "    $dev\n";
	    foreach my $key (keys %{$STATUS{$pool}{$vdev}{$dev}}) {
		print "      key = ".$STATUS{$pool}{$vdev}{$dev}{$key}."\n";
	    }
	    print "\n";
	}
	print "\n";
    }
}
