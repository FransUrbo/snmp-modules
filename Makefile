# Nothing for you here! This is simply for me, so that I'll can do some
# general CVS stuff easily.

DATE    := $(shell date +"%b %e %Y")
TMPDIR  := $(shell tempfile)

BIND9_VERSION := $(shell cat bind9/.version | sed 's@\ .*@@')
BIND9_INSTDIR := $(TMPDIR)/bind9-snmp
BACULA_VERSION := $(shell cat bacula/.version | sed 's@\ .*@@')
BACULA_INSTDIR := $(TMPDIR)/bacula-snmp


$(BIND9_INSTDIR):
	@(rm -f $(TMPDIR) && mkdir -p $(BIND9_INSTDIR); \
	  echo "Instdir:   "$(BIND9_INSTDIR))

$(BACULA_INSTDIR):
	@(rm -f $(TMPDIR) && mkdir -p $(BACULA_INSTDIR); \
	  echo "Instdir:   "$(BACULA_INSTDIR))

bind9_tarball: $(BIND9_INSTDIR)
	@(mkdir -p $(BIND9_INSTDIR)/usr/share/snmp/mibs; \
	  cp BAYOUR-COM-MIB.txt $(BIND9_INSTDIR)/usr/share/snmp/mibs/; \
	  mkdir -p $(BIND9_INSTDIR)/etc/snmp; \
	  cp bind9/bind9-snmp-stats.pl $(BIND9_INSTDIR)/etc/snmp/; \
	  mkdir -p $(BIND9_INSTDIR)/usr/share/cacti/resource/snmp_queries; \
	  cp bind9/bind9-stats*.xml $(BIND9_INSTDIR)/usr/share/cacti/resource/snmp_queries/; \
	  mkdir -p $(BIND9_INSTDIR)/tmp; \
	  cp bind9/cacti_host_template_bind9_snmp_machine.xml $(BIND9_INSTDIR)/tmp; \
	  cd $(BIND9_INSTDIR); \
	  tar czf ../bind9-snmp_$(BIND9_VERSION).tgz `find -type f`; \
	  tar cjf ../bind9-snmp_$(BIND9_VERSION).tar.bz2 `find -type f`; \
	  zip ../bind9-snmp_$(BIND9_VERSION).zip `find -type f`)

bind9_changes:
	@(echo "Date: $(DATE)"; \
	  cat bind9/CHANGES | sed "s@TO BE ANNOUNCED@Release \($(DATE)\)@" > bind9/CHANGES.new; \
	  mv bind9/CHANGES.new bind9/CHANGES; \
	  cvs commit -m "New release - $(BIND9_VERSION)" bind9/CHANGES)

bacula_tarball: $(BACULA_INSTDIR)
	@(mkdir -p $(BACULA_INSTDIR)/usr/share/snmp/mibs; \
	  cp BAYOUR-COM-MIB.txt $(BACULA_INSTDIR)/usr/share/snmp/mibs/; \
	  mkdir -p $(BACULA_INSTDIR)/etc/snmp; \
	  cp bacula/bacula-snmp-stats.pl $(BACULA_INSTDIR)/etc/snmp/; \
	  mkdir -p $(BACULA_INSTDIR)/usr/share/cacti/resource/snmp_queries; \
	  cp bacula/bacula-stats*.xml $(BACULA_INSTDIR)/usr/share/cacti/resource/snmp_queries/; \
	  mkdir -p $(BACULA_INSTDIR)/tmp; \
	  cp bacula/cacti_data_query_snmp_local_bacula_statistics_*.xml $(BACULA_INSTDIR)/tmp; \
	  cd $(BACULA_INSTDIR); \
	  tar czf ../bacula-snmp_$(BACULA_VERSION).tgz `find -type f`; \
	  tar cjf ../bacula-snmp_$(BACULA_VERSION).tar.bz2 `find -type f`; \
	  zip ../bacula-snmp_$(BACULA_VERSION).zip `find -type f`)

bacula_changes:
	@(echo "Date: $(DATE)"; \
	  cat bacula/CHANGES | sed "s@TO BE ANNOUNCED@Release \($(DATE)\)@" > bacula/CHANGES.new; \
	  mv bacula/CHANGES.new bacula/CHANGES; \
	  cvs commit -m "New release - $(BACULA_VERSION)" bacula/CHANGES)

check_mib:
# Bug in the tool - Ignore: 'warning: index element.*should be not-accessible in SMIv2 MIB'
	smilint BAYOUR-COM-MIB.txt

clean:
	@(find -name '*~' -o -name '.*~' -o -name '.#*' -o -name '#*' | \
	  xargs --no-run-if-empty rm)
