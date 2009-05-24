PACKAGE = gmusicbrowser
VERSION = 1.0


prefix		= usr
bindir 		= ${DESTDIR}/${prefix}/bin
appdir		= ${DESTDIR}/${prefix}/share/applications
datadir		= ${DESTDIR}/${prefix}/share
mandir		= ${DESTDIR}/${prefix}/share/man
docdir		= ${DESTDIR}/${prefix}/share/doc/$(PACKAGE)-${VERSION}
localedir	= ${DESTDIR}/${prefix}/share/locale
menudir		= ${DESTDIR}/${prefix}/lib/menu
iconsdir	= ${DESTDIR}/${prefix}/share/icons
liconsdir	= $(iconsdir)/large
miconsdir	= $(iconsdir)/mini

DOCS=AUTHORS COPYING README NEWS INSTALL layout_doc.html
LINGUAS=`/bin/ls locale`

all:
clean:
distclean: clean

install: all
	mkdir -p "$(bindir)"
	mkdir -p "$(datadir)/gmusicbrowser/"
	mkdir -p "$(docdir)"
	mkdir -p "$(mandir)/man1/"
	install -m 644 $(DOCS) "$(docdir)"
	install -m 644 gmusicbrowser.man "$(mandir)/man1/gmusicbrowser.1"
	install -d "$(datadir)/gmusicbrowser/pix/"
	install -d "$(datadir)/gmusicbrowser/pix/gnome-classic/"
	install -d "$(datadir)/gmusicbrowser/pix/tango/"
	install -d "$(datadir)/gmusicbrowser/plugins/"
	install -Dm 755 gmusicbrowser.pl "$(bindir)/gmusicbrowser"
	install -m 755 iceserver.pl      "$(datadir)/gmusicbrowser/iceserver.pl"
	install -m 644 *.pm layouts      "$(datadir)/gmusicbrowser/"
	install -m 644 plugins/*.pm      "$(datadir)/gmusicbrowser/plugins/"
	install -m 644 pix/*.png         "$(datadir)/gmusicbrowser/pix/"
	install -m 644 pix/gnome-classic/*    "$(datadir)/gmusicbrowser/pix/gnome-classic/"
	install -m 644 pix/tango/*            "$(datadir)/gmusicbrowser/pix/tango/"
	install -Dm 644 gmusicbrowser.desktop "$(datadir)/applications/gmusicbrowser.desktop"
	install -Dm 644 gmusicbrowser.menu    "$(menudir)/gmusicbrowser"
	install -Dm 644 pix/gmusicbrowser32x32.png "$(iconsdir)/gmusicbrowser.png"
	install -Dm 644 pix/gmusicbrowser.png      "$(liconsdir)/gmusicbrowser.png"
	install -Dm 644 pix/trayicon.png           "$(miconsdir)/gmusicbrowser.png"
	for lang in $(LINGUAS) ; \
	do \
		install -d "$(localedir)/$$lang/LC_MESSAGES/"; \
		install -m 644 locale/$$lang/LC_MESSAGES/gmusicbrowser.mo	"$(localedir)/$$lang/LC_MESSAGES/"; \
	done

postinstall:
	update-menus

uninstall:
	rm -f "$(bindir)/gmusicbrowser"
	rm -rf "$(datadir)/gmusicbrowser/" "$(docdir)"
	rm -f "$(liconsdir)/gmusicbrowser.png" "$(miconsdir)/gmusicbrowser.png" "$(iconsdir)/gmusicbrowser.png"
	rm -f "$(appdir)/gmusicbrowser.desktop" "$(menudir)/gmusicbrowser"
	rm -f "$(mandir)/$(MANS)"
	rm -f "$(localedir)/*/LC_MESSAGES/gmusicbrowser.mo"

postuninstall:
	#clean_menus
	update-menus
