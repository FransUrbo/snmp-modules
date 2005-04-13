# Nothing for you here! This is simply for me, so that I'll can do some
# general CVS stuff easily.

DATE    := $(shell date +"%b %e %Y")
VERSION := $(shell cat .version | sed 's@\ .*@@')
TMPDIR  := $(shell tempfile)
INSTDIR := $(TMPDIR)/bind9-snmp

$(INSTDIR):
	@(rm -f $(TMPDIR) && mkdir -p $(INSTDIR); \
	  echo "Instdir:   "$(INSTDIR))

install:
	@rcp -x BAYOUR-COM-MIB.txt root@aurora:/usr/share/snmp/mibs/
	@rcp -x bind9-snmp-stats.pl root@aurora:/etc/snmp/
	@rcp -x bind9-stats.xml root@aurora:/usr/share/cacti/resource/snmp_queries/

	@scp BAYOUR-COM-MIB.txt root@anton.swe.net:/usr/share/snmp/mibs/
	@scp bind9-snmp-stats.pl root@anton.swe.net:/etc/snmp/
	@scp  bind9-stats.xml root@anton.swe.net:/usr/share/cacti/resource/snmp_queries/

	@scp BAYOUR-COM-MIB.txt root@alma.swe.net:/usr/share/snmp/mibs/
	@scp bind9-snmp-stats.pl root@alma.swe.net:/etc/snmp/
	@scp  bind9-stats.xml root@alma.swe.net:/usr/share/cacti/resource/snmp_queries/

test: $(INSTDIR)

tarball: $(INSTDIR)
	@(VERSION=`cat .version | sed 's@ .*@@'`; \
	  mkdir -p $(INSTDIR)/usr/share/snmp/mibs; \
	  cp BAYOUR-COM-MIB.txt $(INSTDIR)/usr/share/snmp/mibs/; \
	  mkdir -p $(INSTDIR)/etc/snmp; \
	  cp bind9-snmp-stats.pl $(INSTDIR)/etc/snmp/; \
	  mkdir -p $(INSTDIR)/usr/share/cacti/resource/snmp_queries; \
	  cp bind9-stats.xml $(INSTDIR)/usr/share/cacti/resource/snmp_queries/; \
	  cd $(INSTDIR); \
	  tar czf ../bind9-snmp_$$VERSION.tgz .)

changes:
	@(echo "Date: $(DATE)"; \
	  cat CHANGES | sed "s@TO BE ANNOUNCED@Release \($(DATE)\)@" > CHANGES.new; \
	  mv CHANGES.new CHANGES; \
	  cvs commit -m "New release - `cat .version | sed 's@ .*@@'`" CHANGES)
clean:
	@(find -name '*~' -o -name '.*~' -o -name '.#*' -o -name '#*' | \
	  xargs --no-run-if-empty rm)
