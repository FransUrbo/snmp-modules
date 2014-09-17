This is a pass-through script for SNMP that gives
all the ZFS statistics that can be (is) retreived
using 'zpool' and 'zfs'.

There's a lot of scripts that can retreive ZFS stats
via SNMP but what's making this one special is that
it's indexed and 'tablified'.

Do note that for the moment (until ZoL get's delegation),
the snmp daemon needs to run as root to be able to
retreive the relevant information...


Any patches or fixes will only be accepted against
the GIT version!

                        !!!!! NOTE !!!!!
   Paths below depend on  where your SNMP/Cacti is installed! Examples
   shown for a Debian GNU/Linux system!!
                        !!!!! NOTE !!!!!

                        !!!!! NOTE !!!!!
   Because of a bug in ZoL version <0.6.4, reading DBUF info (the
   zfsDbufStatsTable table), reading DBUF values from /proc/spl/kstat/zfs/dbufs
   is disabled. If you want to enable it, look for the lines:

	     # ---------------------------------
	     # Get DBUFS status information
	# Could be dangerous - see https://github.com/zfsonlinux/zfs/issues/2495
	#    %DBUFS = &get_dbufs_stats();

   Remove the dash at the front of that last line. There is a fix,
   but it have yet to be merged/issued.
                        !!!!! NOTE !!!!!

SNMP Setup files
================
* BAYOUR-COM-MIB.txt
  This is the MIB declaration.
  Copy to /usr/share/mibs/

* BayourCOM_SNMP.pm
  This is the Perl API library needed
  by the zfs-snmp-stats.pl perl script.
  Copy to /usr/local/lib/site_perl/

* zfs-snmp-stats.pl
  This is the stat retreival script.
  Copy to /etc/snmp/

* snmp.conf.stub
  This is part of the snmp.conf file.
  Add to the end of /etc/snmp/snmp.conf

* snmpd.conf.stub
  This is part of the snmpd.conf file.
  Add to the end of /etc/snmp/snmpd.conf

* config file
  This is part of the perl script and contains
  configuration settings (such as where commands
  is located etc).
  Create /etc/zfs/.zfssnmp with the following content:

----- s n i p -----
DEBUG=4
DEBUG_FILE=/tmp/zfs-snmp.log
ZPOOL=/usr/sbin/zpool
ZFS=/usr/sbin/zfs
KSTATDIR=/proc/spl/kstat/zfs
RELOAD=10
----- s n i p -----

Testing
=================
1. Make sure that snmpd actually loads the MIB file
   by executing the command:

     snmpd -f -DALL 2>&1 | grep BAYOUR-COM-MIB

   This will return something like this:

     parse-mibs:   Module 56 BAYOUR-COM-MIB is in /usr/share/snmp/mibs/BAYOUR-COM-MIB.txt
     parse-file: Parsing file:  /usr/share/snmp/mibs/BAYOUR-COM-MIB.txt...
     parse-mibs: Parsing MIB: 56 BAYOUR-COM-MIB
     parse-mibs: Processing IMPORTS for module 56 BAYOUR-COM-MIB
     parse-file: End of file (/usr/share/snmp/mibs/BAYOUR-COM-MIB.txt)
     handler::register: Registering pass_persist (::old_api) at BAYOUR-COM-MIB::bind9Stats
     register_mib: registering "pass_persist" at BAYOUR-COM-MIB::bind9Stats with context ""

2. Test that the script can read the statistics from
   the commands and output information and not have
   any errors.
   Do this by executing the following command:

     zfs-snmp-stats.pl --all > /dev/null

   You should NOT get any output. Any output here
   is errors!

   Next see if it output the correct values. This
   is done with the same command, but without the
   redirect:

     zfs-snmp-stats.pl --all

   The output depends on number of filesystems, zvolumes
   and pools and the actual statistics gathered, so I can't
   show you how it should look like.

3. Check that the script works in a SNMP environment.
   Start the script without parameters

     zfs-snmp-stats.pl

   a. Then on the 'command line' that is given, enter the
      word 'PING' and a newline. The script should reply
      with a simple 'PONG'.

   b. Try to get the number of total pools by entering the
      two following lines:

        get
        .1.3.6.1.4.1.8767.2.6.1.0

      The script should reply with the following lines:
        .1.3.6.1.4.1.8767.2.6.1.0
        integer
        2

      Last line (the number '2') depends on number of pools
      in your storage server.

4. Check that you can retreive values with 'snmpget'
   and 'snmptable' something like this:

   a. snmpget -v 2c -c private localhost .1.3.6.1.4.1.8767.2.6.1.0
   b. snmpget -v 2c -c private localhost zfsTotalPools.0

   Both of these commands should return the number of
   pools in your Bind9 server, something like this:

	.1.3.6.1.4.1.8767.2.6.1.0 = INTEGER: 4

   c. snmptable -v 2c -c private localhost .1.3.6.1.4.1.8767.2.6.5
   d. snmptable -v 2c -c private localhost zfsPoolStatusTable

	----- s n i p -----
	SNMP table: BAYOUR-COM-MIB::zfsPoolStatusTable

	 zfsPoolName zfsPoolSize zfsPoolAlloc zfsPoolFree zfsPoolCap zfsPoolDedup zfsPoolHealth zfsPoolAltRoot
	       test1   429496729       967680   429496729          0         1.00        ONLINE              -
	       test2   429496729       959488   429496729          0         1.00        ONLINE              -
	       test3   429496729       968704   429496729          0         1.00        ONLINE              -
	       test4    68681728       223232    68472012          0         1.00      DEGRADED              -
	----- s n i p -----

   This command is the most interesting. It will give the actual
   pool statistics data.
   Instead of 'snmptable', you can use 'snmpwalk' (same options)
   to get the data in a slightly different view on the data.
