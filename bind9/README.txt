These are some of my SNMP scripts.
* Paths depend on where your SNMP/Cacti installed!

SNMP Setup files
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
cvs -d :pserver:anonymous@cvs.bayour.com:/var/cvs co snmp
