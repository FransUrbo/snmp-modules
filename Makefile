# Nothing for you here! This is simply for me, so that I'll can do some
# general CVS stuff easily.

DATE    := $(shell date +"%b %e %Y")
TMPDIR  := $(shell tempfile)

# ---------------------------------
BIND9_VERSION := $(shell cat bind9/.version | sed 's@\ .*@@')
BIND9_INSTDIR := bind9-snmp-$(BIND9_VERSION)

BACULA_VERSION := $(shell cat bacula/.version | sed 's@\ .*@@')
BACULA_INSTDIR := bacula-snmp-$(BACULA_VERSION)

SYSTEM_VERSION := $(shell cat system/.version | sed 's@\ .*@@')
SYSTEM_INSTDIR := system-snmp-$(SYSTEM_VERSION)

PACKAGE_VERSION := $(shell cat package/.version | sed 's@\ .*@@')
PACKAGE_INSTDIR := package-snmp-$(PACKAGE_VERSION)

# ---------------------------------
$(BIND9_INSTDIR):
	@(if [ -f $(TMPDIR) ]; then \
	    rm -f $(TMPDIR); \
	  fi; \
	  mkdir -p $(TMPDIR)/$(BIND9_INSTDIR); \
	  echo "Instdir:   "$(TMPDIR)/$(BIND9_INSTDIR))

$(BACULA_INSTDIR):
	@(if [ -f $(TMPDIR) ]; then \
	    rm -f $(TMPDIR); \
	  fi; \
	  mkdir -p $(TMPDIR)/$(BACULA_INSTDIR); \
	  echo "Instdir:   "$(TMPDIR)/$(BACULA_INSTDIR))

$(SYSTEM_INSTDIR):
	@(if [ -f $(TMPDIR) ]; then \
	    rm -f $(TMPDIR); \
	  fi; \
	  mkdir -p $(TMPDIR)/$(SYSTEM_INSTDIR); \
	  echo "Instdir:   "$(TMPDIR)/$(SYSTEM_INSTDIR))

$(PACKAGE_INSTDIR):
	@(if [ -f $(TMPDIR) ]; then \
	    rm -f $(TMPDIR); \
	  fi; \
	  mkdir -p $(TMPDIR)/$(PACKAGE_INSTDIR); \
	  echo "Instdir:   "$(TMPDIR)/$(PACKAGE_INSTDIR))

# ---------------------------------
bind9_tarball: $(BIND9_INSTDIR)
	@(cp BAYOUR-COM-MIB.txt BayourCOM_SNMP.pm $(TMPDIR)/$(BIND9_INSTDIR)/; \
	  cp bind9/bind9-snmp-stats.pl $(TMPDIR)/$(BIND9_INSTDIR)/; \
	  cp bind9/bind9-stats*.xml $(TMPDIR)/$(BIND9_INSTDIR)/; \
	  cp bind9/cacti_host_template_bind9_snmp_machine.xml $(TMPDIR)/$(BIND9_INSTDIR)/; \
	  cp bind9/{README,UPGRADE}.txt bind9/snmp*.stub $(TMPDIR)/$(BIND9_INSTDIR)/; \
	  cd $(TMPDIR)/; \
	  tar czf bind9-snmp_$(BIND9_VERSION).tgz `find $(BIND9_INSTDIR) -type f`; \
	  tar cjf bind9-snmp_$(BIND9_VERSION).tar.bz2 `find $(BIND9_INSTDIR) -type f`; \
	  zip bind9-snmp_$(BIND9_VERSION).zip `find $(BIND9_INSTDIR) -type f` > /dev/null)

bind9_changes:
	@(echo "Date: $(DATE)"; \
	  cat bind9/CHANGES | sed "s@TO BE ANNOUNCED@Release \($(DATE)\)@" > bind9/CHANGES.new; \
	  mv bind9/CHANGES.new bind9/CHANGES; \
	  cvs commit -m "New release - $(BIND9_VERSION)" bind9/CHANGES)

# ---------------------------------
bacula_tarball: $(BACULA_INSTDIR)
	@(cp BAYOUR-COM-MIB.txt BayourCOM_SNMP.pm $(TMPDIR)/$(BACULA_INSTDIR)/; \
	  cp bacula/bacula-snmp-stats.pl $(TMPDIR)/$(BACULA_INSTDIR)/; \
	  cp bacula/bacula-stats*.xml $(TMPDIR)/$(BACULA_INSTDIR)/; \
	  cp bacula/cacti_data_query_snmp_local_bacula_statistics_*.xml $(TMPDIR)/$(BACULA_INSTDIR)/; \
	  cd $(TMPDIR); \
	  tar czf bacula-snmp_$(BACULA_VERSION).tgz `find $(BACULA_INSTDIR) -type f`; \
	  tar cjf bacula-snmp_$(BACULA_VERSION).tar.bz2 `find $(BACULA_INSTDIR) -type f`; \
	  zip bacula-snmp_$(BACULA_VERSION).zip `find $(BACULA_INSTDIR) -type f` > /dev/null)

bacula_changes:
	@(echo "Date: $(DATE)"; \
	  cat bacula/CHANGES | sed "s@TO BE ANNOUNCED@Release \($(DATE)\)@" > bacula/CHANGES.new; \
	  mv bacula/CHANGES.new bacula/CHANGES; \
	  cvs commit -m "New release - $(BACULA_VERSION)" bacula/CHANGES)

# ---------------------------------
system_tarball: $(SYSTEM_INSTDIR)
	@(cp BAYOUR-COM-MIB.txt BayourCOM_SNMP.pm $(TMPDIR)/$(SYSTEM_INSTDIR)/; \
	  cp system/system-snmp-stats.pl $(TMPDIR)/$(SYSTEM_INSTDIR)/; \
	  cd $(TMPDIR); \
	  tar czf system-snmp_$(SYSTEM_VERSION).tgz `find $(SYSTEM_INSTDIR) -type f`; \
	  tar cjf system-snmp_$(SYSTEM_VERSION).tar.bz2 `find $(SYSTEM_INSTDIR) -type f`; \
	  zip system-snmp_$(SYSTEM_VERSION).zip `find $(SYSTEM_INSTDIR) -type f` > /dev/null)

system_changes:
	@(echo "Date: $(DATE)"; \
	  cat system/CHANGES | sed "s@TO BE ANNOUNCED@Release \($(DATE)\)@" > system/CHANGES.new; \
	  mv system/CHANGES.new system/CHANGES; \
	  cvs commit -m "New release - $(SYSTEM_VERSION)" system/CHANGES)

# ---------------------------------
package_tarball: $(PACKAGE_INSTDIR)
	@(cp BAYOUR-COM-MIB.txt BayourCOM_SNMP.pm $(TMPDIR)/$(PACKAGE_INSTDIR)/; \
	  cp package/package-snmp-stats.pl $(TMPDIR)/$(PACKAGE_INSTDIR)/; \
	  cd $(TMPDIR); \
	  tar czf package-snmp_$(PACKAGE_VERSION).tgz `find $(PACKAGE_INSTDIR) -type f`; \
	  tar cjf package-snmp_$(PACKAGE_VERSION).tar.bz2 `find $(PACKAGE_INSTDIR) -type f`; \
	  zip package-snmp_$(PACKAGE_VERSION).zip `find $(PACKAGE_INSTDIR) -type f` > /dev/null)

package_changes:
	@(echo "Date: $(DATE)"; \
	  cat package/CHANGES | sed "s@TO BE ANNOUNCED@Release \($(DATE)\)@" > package/CHANGES.new; \
	  mv package/CHANGES.new package/CHANGES; \
	  cvs commit -m "New release - $(PACKAGE_VERSION)" package/CHANGES)

check_mib:
# Bug in the tool - Ignore: 'warning: index element.*should be not-accessible in SMIv2 MIB'
	smilint BAYOUR-COM-MIB.txt

clean:
	@(find -name '*~' -o -name '.*~' -o -name '.#*' -o -name '#*' | \
	  xargs --no-run-if-empty rm)
