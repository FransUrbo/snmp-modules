This is a pass-through script for SNMP that gives
all the Bind9 statistics that can be (is) retreived
with 'rndc status'.

There's a lot of scripts that can retreive Bind9 stats
via SNMP but what's making this one special is that
it's indexed and 'tablified'.


Current release is: 1.1
Tarball:            http://www.bayour.com/bind9-snmp/bind9-snmp_1.1.tgz


SNMP Setup files (Paths depend on where your SNMP/Cacti is installed!)
=================
BAYOUR-COM-MIB.txt	This is the MIB declaration.
			Copy to /usr/share/snmp/mibs/

bind9-snmp-stats.pl	This is the stat retreival script.
			Copy to /etc/snmp/

snmp.conf.stub		This is part of the snmp.conf file.
			Add to the end of /etc/snmp/snmp.conf

snmpd.conf.stub		This is part of the snmpd.conf file.
			Add to the end of /etc/snmp/snmpd.conf


Cacti setup files
=================
bind9-stats_domains.xml	Domain vise statistics
bind9-stats_totals.xml	Total statistic numbers
			These are the XML declaration for cacti.
			Copy to /usr/share/cacti/resource/snmp_queries/

cacti_data_query_snmp_local_bind9_statistics_domains.xml
cacti_data_query_snmp_local_bind9_statistics_totals.xml
			This is all the templates to import into
			cacti to retreive Bind9 statistics via
			a Indexed SNMP query.



NOTE:
The latest version of these files can be found via anonymous cvs
(just press the ENTER key when asked for a password):

cvs -d :pserver:anonymous@cvs.bayour.com:/var/cvs login
cvs -d :pserver:anonymous@cvs.bayour.com:/var/cvs co bind9-snmp

There's a web to cvs gateway at the URL:
http://apache.bayour.com/cgi-bin/cvsweb/snmp-modules/bind9/
