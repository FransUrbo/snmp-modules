The file BayourCOM_SNMP.pm must be copied into a directory
where perl can find it (i.e. in one of it's include directories).

These directories can be shown by executing the following command
line:

	perl -e "foreach \$dir (@INC) { print \"\$dir\n\"; }" | sort
