This is a pass-through script for SNMP that gives
all the Bind9 statistics that can be (is) retreived
with 'rndc stats'.

There's a lot of scripts that can retreive Bind9 stats
via SNMP but what's making this one special is that
it's indexed and 'tablified'.


Current release is: 1.5
Tarball:            http://www.bayour.com/bind9-snmp/bind9-snmp_1.5.tgz


SNMP Setup files (Paths depend on where your SNMP/Cacti is installed!)
=================
* BAYOUR-COM-MIB.txt
  This is the MIB declaration.
  Copy to /usr/share/snmp/mibs/

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
to the 'cvs-snmp-modules@bayour.com' mailinglist. It contain ALL my
SNMP modules, not just the Bind9 SNMP Subagent changes. It's not that
much traffic on the list, so don't worry about 'drowning' :).

For support and other discussions about the module, please subscribe
to the 'snmp-modules@bayour.com' mailinglist.

To subscribe: Send an empty mail to the 'request-<mailinglist>' address.

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
STATS_FILE=/var/lib/named/var/log/dns-stats.log
STATS_FILE_OWNER_GROUP=bind9.bind9
RNDC=/usr/sbin/rndc
DELTA_DIR=/var/tmp/
----- s n i p -----
