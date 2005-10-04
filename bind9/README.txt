This is a pass-through script for SNMP that gives
all the Bind9 statistics that can be (is) retreived
with 'rndc stats'.

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
	This is all the templates to import into  cacti to retreive Bind9
	statistics via a Indexed SNMP query.

cacti_data_query_snmp_local_bind9_statistics_dependencies.xml
	Loading the templates above will give dependency errors from
	cacti. This is because the're referencing (for example) 'Get SNMP Data
	(Indexed)' (which is distributed with Cacti by default) with a hash
	value on _MY_ Cacti installation.  Your's will have different values...

	The best (most secure I guess) way is to extract YOUR hash values
	from YOUR installation and then insert them into the template
	files above. This is however very user-unfriendly (to say the
	least) and very time consuming (you have to do it manually).

	There's more information about this in the cacti-user mailinglist
	archives. Unfortunatly, I'm not sure what the PERFECT way is...
	http://sourceforge.net/mailarchive/message.php?msg_id=11634191
	http://sourceforge.net/mailarchive/forum.php?thread_id=7632776&forum_id=12795

	In these threads, it is/was discussed that adding this dependency
	file to BOTH of the template XML file (in the correct way/place)
	WORKS. But DO NOT recommend it! Do not blame me if that way fucks
	up your Cacti installation. YOU HAVE BEEN WARNED!

NOTE:
The latest version of these files can be found via anonymous cvs
(just press the ENTER key when asked for a password):

cvs -d :pserver:anonymous@cvs.bayour.com:/var/cvs login
cvs -d :pserver:anonymous@cvs.bayour.com:/var/cvs co bind9-snmp

There's a web to cvs gateway at the URL:
http://apache.bayour.com/cgi-bin/cvsweb/snmp-modules/bind9/
