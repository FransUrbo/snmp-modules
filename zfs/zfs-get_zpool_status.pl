#!/usr/bin/perl -w

use strict;
my %pool_status = ('DEGRADED'	=> 1,
		   'FAULTED'	=> 2,
		   'OFFLINE'	=> 3,
		   'ONLINE'	=> 4,
		   'REMOVED'	=> 5,
		   'UNAVAIL'	=> 6);
my(%CFG);
$CFG{'ZPOOL'} = "zpool";

# ========================================

sub zpool_get_status {
    my($pool, $state, $vdev, %status, $devices);
    $devices = 0;

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

	    # Next line after the header is the pool status line
	    $zpool = <ZPOOL>;
	    chomp($zpool);

	    my $dev = (split(' ', $zpool))[0];

	    ($status{$dev}{'name'}, $status{$dev}{'state'}, $status{$dev}{'read'},
	     $status{$dev}{'write'}, $status{$dev}{'cksum'}) = split(' ', $zpool);

	    # Translate the status to a number according to %pool_status
	    foreach my $stat (keys %pool_status) {
		if ($status{$dev}{'state'} eq $stat) {
		    $status{$dev}{'state'} = $pool_status{$stat};
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

	    ($status{$dev}{'name'}, $status{$dev}{'state'}, $status{$dev}{'read'},
	     $status{$dev}{'write'}, $status{$dev}{'cksum'}) = split(' ', $zpool);

	    # Translate the status to a number according to %pool_status
	    foreach my $stat (keys %pool_status) {
		if ($status{$dev}{'state'} eq $stat) {
		    $status{$dev}{'state'} = $pool_status{$stat};
		}
	    }

	    $devices++;
	}
    }

    close(ZPOOL);

    return($devices, %status);
}

# ========================================

my ($devs, %stats) = &zpool_get_status();
foreach my $dev (keys %stats) {
    print "$dev\n";
    foreach my $key (keys %{$stats{$dev}}) {
	print "  key = ".$stats{$dev}{$key}."\n";
    }
    print "\n";
}
