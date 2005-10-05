# Nothing for you here! This is simply for me, so that I'll can do some
# general CVS stuff easily.

DATE    := $(shell date +"%b %e %Y")
TMPDIR  := $(shell tempfile)

BIND9_VERSION := $(shell cat bind9/.version | sed 's@\ .*@@')
BIND9_INSTDIR := $(TMPDIR)/bind9-snmp

$(BIND9_INSTDIR):
	@(rm -f $(TMPDIR) && mkdir -p $(BIND9_INSTDIR); \
	  echo "Instdir:   "$(BIND9_INSTDIR))

install:
	@rcp -x BAYOUR-COM-MIB.txt root@aurora:/usr/share/snmp/mibs/
	@rcp -x bind9/bind9-snmp-stats.pl root@aurora:/etc/snmp/
	@rcp -x bind9/bind9-stats*.xml root@aurora:/usr/share/cacti/resource/snmp_queries/

	@scp BAYOUR-COM-MIB.txt root@anton.swe.net:/usr/share/snmp/mibs/
	@scp bind9/bind9-snmp-stats.pl root@anton.swe.net:/etc/snmp/
	@scp bind9/bind9-stats*.xml root@anton.swe.net:/usr/share/cacti/resource/snmp_queries/

	@scp BAYOUR-COM-MIB.txt root@alma.swe.net:/usr/share/snmp/mibs/
	@scp bind9/bind9-snmp-stats.pl root@alma.swe.net:/etc/snmp/
	@scp bind9/bind9-stats*.xml root@alma.swe.net:/usr/share/cacti/resource/snmp_queries/

release: bind9_tarball

bind9_tarball: $(BIND9_INSTDIR)
	@(mkdir -p $(BIND9_INSTDIR)/usr/share/snmp/mibs; \
	  cp BAYOUR-COM-MIB.txt $(BIND9_INSTDIR)/usr/share/snmp/mibs/; \
	  mkdir -p $(BIND9_INSTDIR)/etc/snmp; \
	  cp bind9/bind9-snmp-stats.pl $(BIND9_INSTDIR)/etc/snmp/; \
	  mkdir -p $(BIND9_INSTDIR)/usr/share/cacti/resource/snmp_queries; \
	  cp bind9/bind9-stats*.xml $(BIND9_INSTDIR)/usr/share/cacti/resource/snmp_queries/; \
	  mkdir -p $(BIND9_INSTDIR)/tmp; \
	  cp bind9/cacti_data_query_snmp_local_bind9_statistics_*.xml $(BIND9_INSTDIR)/tmp; \
	  cd $(BIND9_INSTDIR); \
	  tar czf ../bind9-snmp_$(BIND9_VERSION).tgz `find -type f`)

bind9_changes:
	@(echo "Date: $(DATE)"; \
	  cat bind9/CHANGES | sed "s@TO BE ANNOUNCED@Release \($(DATE)\)@" > bind9/CHANGES.new; \
	  mv bind9/CHANGES.new bind9/CHANGES; \
	  cvs commit -m "New release - $(BIND9_VERSION)" bind9/CHANGES)

check_mib:
# Bug in the tool - Ignore: 'warning: index element.*should be not-accessible in SMIv2 MIB'
	smilint BAYOUR-COM-MIB.txt

clean:
	@(find -name '*~' -o -name '.*~' -o -name '.#*' -o -name '#*' | \
	  xargs --no-run-if-empty rm)
