%define isaix %(test "`uname -s`" = "AIX" && echo "1" || echo "0")
%define islinux %(test "`uname -s`" = "Linux" && echo "1" || echo "0")

%if %{isaix}
	%define _prefix	/opt/nagios
	%define _docdir %{_prefix}/doc/nrpe-newdate
	%define nshome /opt/nagios
	%define _make gmake
%endif
%if %{islinux}
    %define _prefix	/usr/local/nagios
	%define _init_dir /usr/lib/systemd/system
	%define _init_type systemd
	%define _exec_prefix %{_prefix}/sbin
	%define _bindir %{_prefix}/bin
	%define _sbindir %{_prefix}/lib/nagios/cgi
	%define _libexecdir %{_prefix}/libexec
	%define _datadir %{_prefix}/share
	%define _localstatedir /var/log/nagios
	%define nshome /var/log/nagios
	%define _make make
%endif
%define _sysconfdir /etc

%define name nrpe
%define version 4.0.3
%define release 1
%define nsusr nagios
%define nsgrp nagios
%define nsport 5666
%define ns_src_tmpfile "tmpfile.conf"

# Reserve option to override port setting with:
# rpm -ba|--rebuild --define 'nsport 5666'
%{?port:%define nsport %{port}}

# Macro that print messages to syslog at package (un)install time
%define nnmmsg logger -t %{name}/rpm

Summary: Host/service/network monitoring agent for Nagios
URL: http://www.nagios.org
Name: %{name}
Version: %{version}
Release: %{release}
License: GPL
Group: Application/System
Source0: %{name}-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}-buildroot
Prefix: %{_prefix}
Prefix: /usr/lib/systemd/system
Prefix: /etc/nagios
%if %{isaix}
Requires: nagios-plugins
%endif
%if %{islinux}
Requires: bash, grep, nagios-plugins, util-linux, chkconfig, shadow-utils, sed, initscripts, mktemp
%endif

%description
NPRE (Nagios Remote Plugin Executor) is a system daemon that 
will execute various Nagios plugins locally on behalf of a 
remote (monitoring) host that uses the check_nrpe plugin.  
Various plugins that can be executed by the daemon are available 
at: http://sourceforge.net/projects/nagiosplug

This package provides the client-side NRPE agent (daemon).

%package plugin
Group: Application/System
Summary: Provides nrpe plugin for Nagios.
Requires: nagios-plugins

%description plugin
NPRE (Nagios Remote Plugin Executor) is a system daemon that 
will execute various Nagios plugins locally on behalf of a 
remote (monitoring) host that uses the check_nrpe plugin.  
Various plugins that can be executed by the daemon are available 
at: http://sourceforge.net/projects/nagiosplug

This package provides the server-side NRPE plugin for 
Nagios-related applications.

%prep
%setup -q

%if %{isaix}
# Check to see if the nrpe service is running and, if so, stop it.
/usr/bin/lssrc -s nrpe > /dev/null 2> /dev/null
if [ $? -eq 0 ] ; then
	status=`/usr/bin/lssrc -s nrpe | /usr/bin/gawk '$1=="nrpe" {print $NF}'`
	if [ "$status" = "active" ] ; then
		/usr/bin/stopsrc -s nrpe
	fi
fi
%endif

%if %{isaix}
%post
/usr/bin/lssrc -s nrpe > /dev/null 2> /dev/null
if [ $? -eq 1 ] ; then
	/usr/bin/mkssys -p %{_bindir}/nrpe -s nrpe -u 0 -a "-c %{_sysconfdir}/nrpe.cfg -d -s" -Q -R -S -n 15 -f 9
fi
/usr/bin/startsrc -s nrpe
%endif

%preun
%if %{isaix}
status=`/usr/bin/lssrc -s nrpe | /usr/bin/gawk '$1=="nrpe" {print $NF}'`
if [ "$status" = "active" ] ; then
	/usr/bin/stopsrc -s nrpe
fi
/usr/bin/rmssys -s nrpe
%endif
%if %{islinux}
if [ "$1" = 0 ]; then
	/sbin/service nrpe stop > /dev/null 2>&1
	/sbin/chkconfig --del nrpe
fi
%endif

%if %{islinux}
%postun
if [ "$1" -ge "1" ]; then
	/sbin/service nrpe condrestart >/dev/null 2>&1 || :
fi
%endif

%build
export PATH=$PATH:/usr/sbin
CFLAGS="$RPM_OPT_FLAGS" CXXFLAGS="$RPM_OPT_FLAGS" \
MAKE=%{_make} ./configure \
	--with-init-type=%{_init_type} \
	--with-nrpe-port=%{nsport} \
	--with-nrpe-user=%{nsusr} \
	--with-nrpe-group=%{nsgrp} \
	--prefix=%{_prefix} \
	--exec-prefix=%{_exec_prefix} \
	--bindir=%{_bindir} \
	--sbindir=%{_sbindir} \
	--libexecdir=%{_libexecdir} \
	--datadir=%{_datadir} \
	--sysconfdir=%{_sysconfdir} \
	--localstatedir=%{_localstatedir} \
	--enable-command-args
%{_make} all

%install
[ "$RPM_BUILD_ROOT" != "/" ] && rm -rf $RPM_BUILD_ROOT
%if %{islinux}
install -d -m 0755 ${RPM_BUILD_ROOT}%{_init_dir}
%endif
DESTDIR=${RPM_BUILD_ROOT} %{_make} install-groups-users install install-config install-init


%clean
rm -rf $RPM_BUILD_ROOT


%files
%if %{islinux}
%defattr(755,root,root)
/usr/lib/systemd/system/nrpe.service
%endif
%{_bindir}/nrpe
%dir %{_sysconfdir}
%defattr(600,%{nsusr},%{nsgrp})
%config(noreplace) %{_sysconfdir}/*.cfg
%defattr(755,%{nsusr},%{nsgrp})
%if %{ns_src_tmpfile} != ""
/usr/lib/tmpfiles.d/nrpe.conf
%endif
%{_bindir}/nrpe-uninstall
%doc CHANGELOG.md LEGAL README.md README.SSL.md SECURITY.md

%files plugin
%defattr(755,%{nsusr},%{nsgrp})
%{_libexecdir}
%defattr(644,%{nsusr},%{nsgrp})
%doc CHANGELOG.md LEGAL README.md

%changelog
* Thu Aug 18 2016 John Frickson jfrickson<@>nagios.com
- Changed 'make install-daemon-config' to 'make install-config'
- Added make targets 'install-groups-users' and 'install-init'
- Misc. changes

* Mon Mar 12 2012 Eric Stanley estanley<@>nagios.com
- Created autoconf input file 
- Updated to support building on AIX
- Updated install to use make install*

* Mon Jan 23 2006 Andreas Kasenides ank<@>cs.ucy.ac.cy
- fixed nrpe.cfg relocation to sample-config
- replaced Copyright label with License
- added --enable-command-args to enable remote arg passing (if desired can be disabled by commenting out)

* Wed Nov 12 2003 Ingimar Robertsson <iar@skyrr.is>
- Added adding of nagios group if it does not exist.

* Tue Jan 07 2003 James 'Showkilr' Peterson <showkilr@showkilr.com>
- Removed the lines which removed the nagios user and group from the system
- changed the patch release version from 3 to 1

* Mon Jan 06 2003 James 'Showkilr' Peterson <showkilr@showkilr.com>
- Removed patch files required for nrpe 1.5
- Update spec file for version 1.6 (1.6-1)

* Sat Dec 28 2002 James 'Showkilr' Peterson <showkilr@showkilr.com>
- First RPM build (1.5-1)
