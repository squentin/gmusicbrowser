Name: gmusicbrowser
Summary: Jukebox for large collections of mp3/ogg/flac/mpc files
Version: 1.1.8
Release: 1
License: GPL
Group: Sound
URL: http://gmusicbrowser.org/
Source0: http://gmusicbrowser.org/download/%{name}-%{version}.tar.gz
#Source0: %{name}-%{version}.tar.gz
Packager: Quentin Sculo <squentin@free.fr>
Buildroot: %{_tmppath}/%{name}-%{version}-%{release}-root
BuildArch: noarch
Requires: perl >= 5.8, gtk2 >= 2.6.0, perl-Gtk2, perl(Locale::gettext) >= 1.04, perl-GStreamer, perl-Digest-CRC, perl-Cairo, perl-HTML-Parser perl-IO-Compress, perl-Net-DBus
Requires(hint): mpg123, vorbis-tools, alsa-utils, perl-Gtk2-WebKit, perl-Gtk2-MozEmbed, perl-Net-DBus-GLib, gstreamer0.10-lame, gstreamer0.10-plugins-ugly, gstreamer0.10-plugins-bad, perl-Gnome2-Wnck, perl-GStreamer-Interfaces, perl-Gtk2-Notify
AutoReq: no
AutoProv: no

%description
Very customizable jukebox for large collections of music files
Uses gstreamer, mpg123/ogg123 or mplayer for playback
Main features :
- customizable window layouts
- artist/album lock : easily restrict playlist to current artist/album
- easy access to related songs (same artist/album/title)
- simple mass-tagging and mass-renaming
- support multiple genres for each song
- customizable labels can be set for each song
- filters with unlimited nesting of conditions
- customizable weighted random mode

%prep
%setup -q
%build
%install
rm -rf %{buildroot}
%makeinstall prefix=%{buildroot}%{_prefix}
rm -f %{buildroot}/%{_menudir}/gmusicbrowser
%find_lang %{name}

%clean
rm -rf %{buildroot}

%post
%{update_menus}
%postun
%{clean_menus}

%files -f %{name}.lang
%defattr(-,root,root,0755)
%{_bindir}/*
%{_datadir}/gmusicbrowser/*
%{_datadir}/applications/gmusicbrowser.desktop
#%lang(fr) %{_datadir}/locale/fr/LC_MESSAGES/*.mo
#%{_datadir}/locale/*/LC_MESSAGES/*.mo
#%{_menudir}/gmusicbrowser
%{_iconsdir}/gmusicbrowser.png
%{_liconsdir}/gmusicbrowser.png
%{_miconsdir}/gmusicbrowser.png
%{_mandir}/man1/*
%{_docdir}/*
#%doc AUTHORS COPYING README NEWS layout_doc.html

%changelog
* Sat Jul 26 2008 Quentin Sculo <squentin@free.fr> 1.0-1
- changed the url to http://gmusicbrowser.sourceforge.net/ as it's more likely to stay valid in the future
- escape macro in changelog
* Fri May 02 2008 Quentin Sculo <squentin@free.fr> 0.964-1
- removed %%{_menudir}/gmusicbrowser
* Mon Oct 29 2007 Quentin Sculo <squentin@free.fr> 0.962-1
- package the doc files with %%{_docdir}/* instead of %%doc
- added perl-GStreamer to required
- updated the long description
* Fri Aug 24 2007 Quentin Sculo <squentin@free.fr> 0.960-1
- replaced perl-Locale-gettext dependency by perl(Locale::gettext), should be more compatible
* Fri Mar 30 2007 Quentin Sculo <squentin@free.fr> 0.958-1
- added perl-Locale-gettext dependency
* Wed Aug 24 2006 Quentin Sculo <squentin@free.fr> 0.955-1
- added locale files
* Fri Nov 11 2005 Quentin Sculo <squentin@free.fr> 0.941-1
- use Makefile, added doc and man files
* Wed Sep 07 2005 Quentin Sculo <squentin@free.fr> 0.933-1
- Initial .spec file
