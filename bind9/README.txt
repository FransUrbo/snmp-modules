This is a pass-through script for SNMP that gives
all the Bind9 statistics that can be (is) retreived
with 'rndc stats'.

There's a lot of scripts that can retreive Bind9 stats
via SNMP but what's making this one special is that
it's indexed and 'tablified'.


Latest version is: 1.pre8 (This is the current CVS version)
Tarball:            http://www.bayour.com/bind9-snmp/bind9-snmp_1.pre8.tgz
Tarball 2:          http://www.bayour.com/bind9-snmp/bind9-snmp_1.pre8.tar.bz2
ZIPfile:            http://www.bayour.com/bind9-snmp/bind9-snmp_1.pre8.zip

Latest stable release is: 1.7 (which apparently don't work to good :)
Tarball:            http://www.bayour.com/bind9-snmp/bind9-snmp_1.7.tgz
Tarball 2:          http://www.bayour.com/bind9-snmp/bind9-snmp_1.7.tar.bz2
ZIPfile:            http://www.bayour.com/bind9-snmp/bind9-snmp_1.7.zip


Any patches or fixes will only be accepted against the CVS version!

                        !!!!! NOTE !!!!!
   Paths below depend on  where your SNMP/Cacti is installed! Examples
   shown for a Debian GNU/Linux system!!
                        !!!!! NOTE !!!!!

SNMP Setup files
================
* BAYOUR-COM-MIB.txt
  This is the MIB declaration.
  Copy to /usr/share/snmp/mibs/

* BayourCOM_SNMP.pm
  This is the Perl API library needed
  by the bind9-snmp-stats.pl perl script.
  Copy to /usr/local/lib/site_perl/

* bind9-snmp-stats.pl
  This is the stat retreival script.
  Copy to /etc/snmp/

* snmp.conf.stub
  This is part of the snmp.conf file.
  Add to the end of /etc/snmp/snmp.conf

* snmpd.conf.stub
  This is part of the snmpd.conf file.
  Add to the end of /etc/snmp/snmpd.conf


Cacti setup files
=================
* bind9-stats_domains.xml	Domain vise statistics
* bind9-stats_totals.xml	Total statistic numbers
  These are the XML declaration for cacti.
  Copy to /usr/share/cacti/resource/snmp_queries/

* cacti_host_template_bind9_snmp_machine.xml
  This is the template to import into cacti to add Bind9 statistic
  graphs to your SNMP hosts.

  This file will create a new host template named 'Bind9 SNMP
  Machine'. See below how to create the graphs..

Adding Bind9 SNMP statistic graphs for your host(s):
=================
To add the Bind9 SNMP graphs and data queries etc to you host(s), got
to 'Devices->[host(s)]->Host Template' and select the 'Bind9 SNMP
Machine' template. It will NOT delete/remove any of your existing
graph template(s) or data queries. Just add the Bind9 SNMP stuff you
need.

1. Click on the 'Create Graphs for this Host' and in the 'Data Query
   [SNMP - Local - Bind9 Statistics - domains - QUERY]' section,
   tick/select all the domains you want statistics for.

2. In the 'Data Query [SNMP - Local - Bind9 Statistics - totals -
   QUERY]' section, tick/select all summaries you want statistics for.

After those two points, click the 'create' button at the bottom left.


Mailinglists
=================
If you're interested in all the CVS commits and changes, you can subscribe
to the 'cvs-snmp-modules@lists.bayour.com' mailinglist. It contain ALL my
SNMP modules, not just the Bind9 SNMP Subagent changes. It's not that
much traffic on the list, so don't worry about 'drowning' :).

For support and other discussions about the module, please subscribe
to the 'snmp-modules@lists.bayour.com' mailinglist.

To subscribe: Send an empty mail to the request-<mailinglist>@lists.bayour.com
address.


NOTE (1):
=================
Some people have had problems getting statistics in previous versions.
This is/was because of a number of problems which should be fixed in
version 1.3 (this version).

IF you've had problems before, got to 'Graph Management', search for
'Any' host and with the search string 'bind9'. Make sure you delete
(!) all entries found. Also make sure to delete all RRD files in the
'<path_rra>' directory - the command 'rm <path_rra>/*_bind9_*.rrd'
should do that. Be sure to replace '<path_rra>' with the full path
to your RRD files (you can find that in the 'Configuration->Settings->Paths'
section...


NOTE (2):
=================
The latest version of these files can be found via anonymous cvs
(just press the ENTER key when asked for a password):

cvs -d :pserver:anonymous@cvs.bayour.com:/var/cvs login
cvs -d :pserver:anonymous@cvs.bayour.com:/var/cvs co bind9-snmp

There's a web to cvs gateway at the URL:
http://apache.bayour.com/cgi-bin/cvsweb/snmp-modules/bind9/


NOTE (3):
=================
As of version 1.4, there a config file you need to create.
This is (by default) '/etc/bind/.bindsnmp'. 

It have the following format (my values as example):

----- s n i p -----
DEBUG=4
DEBUG_FILE=/var/log/bind9-snmp-stats.log
STATS_FILE=/var/log/dns-stats.log
STATS_FILE_OWNER_GROUP=bind9.bind9
RNDC=/usr/sbin/rndc
DELTA_DIR=/var/tmp/
----- s n i p -----


Setting up Bind9 to log statistics
=================
In the named.conf (or wherever you have
your 'options' options), add the following
two lines:

        // Statistics
        zone-statistics yes;
        statistics-file "/var/log/dns-stats.log";

Note the 'statistics-file' and the 'STATS_FILE'
options in named.conf and .bindsnmp respectively!

+ In newer Bind9 (unknown version, but I'm quite
  sure it didn't exist in 9.1 and earlier - it
  DO work in 9.4), it's possible to put the 
  'zone-statistics' option within the actual
  zone instead so that statistics is only gathered
  for specified zones instead of all...


Testing
=================
1. First thing to test is if bind actually creates
   the statistics file.
   Execute the command 'rndc stats' and look at the
   file specified with the statistics-file option.

2. Make sure that snmpd actually loads the MIB file
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

3. Test that the script can read the statistics file
   and output information and not have any errors.
   Do this by executing the following command: 

     bind9-snmp-stats.pl --all > /dev/null

   You should NOT get any output. Any output here
   is errors!

   Next see if it output the correct values. This
   is done with the same command, but without the
   redirect:

     bind9-snmp-stats.pl --all

   The output depends on number of domains and the
   actual statistics gathered, so I can't show you
   how it should look like.

4. Check that the script works in a SNMP environment.
   Start the script without parameters

     bind9-snmp-stats.pl

   a. Then on the 'command line' that is given, enter the
      word 'PING' and a newline. The script should reply
      with a simple 'PONG'.

   b. Try to get the number of total domains by entering the
      the two following lines:

        get
        .1.3.6.1.4.1.8767.2.1.1.0

      The script should reply with the following lines:

        .1.3.6.1.4.1.8767.2.1.1.0
        integer
        6

      Last line (the number '6') depends on number of domains
      in your Bind9 server.

5. Check that you can retreive values with 'snmpget'
   and 'snmptable' something like this:

   a. snmpget -v1 -c private localhost .1.3.6.1.4.1.8767.2.1.1.0
   b. snmpget -v1 -c private localhost b9stNumberTotals.0

   Both of these commands should return the number of
   domains in your Bind9 server.

   c. snmptable -v1 -c private localhost .1.3.6.1.4.1.8767.2.1.3
   d. snmptable -v1 -c private localhost b9stTotalsTable

   On my laptop, this doesn't give any good data (because it's
   basically not used - only for testing this script etc), but
   it DO give the correct ones:

      b9stCounterName b9stCounterTotal b9stCounterForward b9stCounterReverse
              success                0                  0                  0
             referral                0                  0                  0
              nxrrset                0                  0                  0
             nxdomain                0                  0                  0
            recursion                0                  0                  0
              failure                0                  0                  0

   e. snmptable -v1 -c private localhost .1.3.6.1.4.1.8767.2.1.4
   f. snmptable -v1 -c private localhost b9stDomainsTable

   This command is the most interesting. It will give the actual
   zone statistics data.
   Instead of 'snmptable', you can use 'snmpwalk' (same options)
   to get the data in a slightly different view on the data.

Test Notes
=================
I have not used this script in a long time (my cacti server
had crashed, and I had not time fixing it), I set up this
script on my laptop. All points up (but not including) point
five worked flawlessly. But point five 'a' did not work! I got
the following message:

  Error in packet
  Reason: (noSuchName) There is no such variable name in this MIB.
  Failed object: BAYOUR-COM-MIB::b9stNumberTotals.0

In my case, this was because the logfile (DEBUG_FILE in the
.bindsnmp config file) could not be written to.
