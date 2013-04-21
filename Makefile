PACKAGE = gmusicbrowser
VERSION = $(shell grep "^ *VERSIONSTRING" gmusicbrowser.pl |head -n 1 |grep -Eo [.0-9]+)


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

# this triggers correct gettext behavior
# unset LINGUAS => installs all supported linguas
# LINGUAS="" => installs none
# LINGUAS="fr ru" => installs only fr and ru
SUPPORTED_LINGUAS=$(shell for l in po/*po; do basename $$l .po; done)
LCMD := if [ -n "$${LINGUAS+x}" ] ; then for f in $(SUPPORTED_LINGUAS) ; do case "$(LINGUAS)" in *$$f*) printf "$$f " ;; esac ; done ; else printf "$(SUPPORTED_LINGUAS)" ; fi
ACTIVE_LINGUAS = $(shell $(LCMD))

MARKDOWN= markdown


all: locale doc
clean:
	rm -rf dist/
distclean: clean
	rm -rf locale/ layout_doc.html

po/gmusicbrowser.pot : gmusicbrowser.pl *.pm plugins/*.pm layouts/*.layout
	perl po/create_pot.pl --quiet

po/%.po : po/gmusicbrowser.pot
	msgmerge -s -U -N $@ po/gmusicbrowser.pot

locale/%/LC_MESSAGES/gmusicbrowser.mo : po/%.po po/gmusicbrowser.pot
	mkdir -p locale/$*/LC_MESSAGES/
	msgfmt --statistics -c -o $@ $<

locale: $(foreach l,$(ACTIVE_LINGUAS),locale/$l/LC_MESSAGES/gmusicbrowser.mo)

checkpo:
	for lang in $(ACTIVE_LINGUAS) ; do msgfmt -c po/$$lang.po -o /dev/null || exit 1 ; done

doc : layout_doc.html

layout_doc.html : layout_doc.mkd
	${MARKDOWN} layout_doc.mkd > layout_doc.html

install: all
	mkdir -p "$(bindir)"
	mkdir -p "$(datadir)/gmusicbrowser/"
	mkdir -p "$(docdir)"
	mkdir -p "$(mandir)/man1/"
	install -pm 644 $(DOCS) "$(docdir)"
	install -pm 644 gmusicbrowser.man "$(mandir)/man1/gmusicbrowser.1"
	install -pd "$(datadir)/gmusicbrowser/pix/"
	install -pd "$(datadir)/gmusicbrowser/pix/elementary/"
	install -pd "$(datadir)/gmusicbrowser/pix/elementary_dark/"
	install -pd "$(datadir)/gmusicbrowser/pix/Faenza/"
	install -pd "$(datadir)/gmusicbrowser/pix/Faenza-Dark/"
	install -pd "$(datadir)/gmusicbrowser/pix/gnome-classic/"
	install -pd "$(datadir)/gmusicbrowser/pix/tango/"
	install -pd "$(datadir)/gmusicbrowser/pix/oxygen/"
	install -pd "$(datadir)/gmusicbrowser/plugins/"
	install -pd "$(datadir)/gmusicbrowser/layouts/"
	install -pDm 755 gmusicbrowser.pl "$(bindir)/gmusicbrowser"
	install -pm 755 iceserver.pl      "$(datadir)/gmusicbrowser/iceserver.pl"
	install -pm 644 *.pm		  "$(datadir)/gmusicbrowser/"
	install -pm 644 gmbrc.default     "$(datadir)/gmusicbrowser/"
	install -pm 644 layouts/*.layout  "$(datadir)/gmusicbrowser/layouts/"
	install -pm 644 plugins/*.pm      "$(datadir)/gmusicbrowser/plugins/"
	install -pm 644 pix/*.png         "$(datadir)/gmusicbrowser/pix/"
	install -pm 644 pix/elementary/*    "$(datadir)/gmusicbrowser/pix/elementary/"
	install -pm 644 pix/elementary_dark/*    "$(datadir)/gmusicbrowser/pix/elementary_dark/"
	install -pm 644 pix/Faenza/*    "$(datadir)/gmusicbrowser/pix/Faenza/"
	install -pm 644 pix/gnome-classic/*    "$(datadir)/gmusicbrowser/pix/gnome-classic/"
	install -pm 644 pix/tango/*            "$(datadir)/gmusicbrowser/pix/tango/"
	install -pm 644 pix/oxygen/*           "$(datadir)/gmusicbrowser/pix/oxygen/"
	install -pDm 644 gmusicbrowser.desktop "$(datadir)/applications/gmusicbrowser.desktop"
	install -pDm 644 gmusicbrowser.menu    "$(menudir)/gmusicbrowser"
	install -pDm 644 pix/gmusicbrowser.svg "$(iconsdir)/gmusicbrowser.png"
	install -pDm 644 pix/gmusicbrowser.png      "$(liconsdir)/gmusicbrowser.png"
	install -pDm 644 pix/trayicon.png           "$(miconsdir)/gmusicbrowser.png"
	for lang in $(ACTIVE_LINGUAS) ; \
	do \
		install -pd "$(localedir)/$$lang/LC_MESSAGES/"; \
		install -pm 644 locale/$$lang/LC_MESSAGES/gmusicbrowser.mo	"$(localedir)/$$lang/LC_MESSAGES/"; \
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

prepackage : all
	perl -pi -e 's!Version:.*!Version: '$(VERSION)'!' gmusicbrowser.spec
	mkdir -p dist/

dist: prepackage
	tar -czf dist/$(PACKAGE)-$(VERSION).tar.gz . --transform=s/^[.]/$(PACKAGE)-$(VERSION)/ --exclude=\*~ --exclude=.git\* --exclude=.\*swp --exclude=./dist && echo wrote dist/$(PACKAGE)-$(VERSION).tar.gz

# release : same as dist, but exclude debian/ folder
release: prepackage
	tar -czf dist/$(PACKAGE)-$(VERSION).tar.gz . --transform=s/^[.]/$(PACKAGE)-$(VERSION)/ --exclude=\*~ --exclude=.git\* --exclude=.\*swp --exclude=./dist --exclude=./debian && echo wrote dist/$(PACKAGE)-$(VERSION).tar.gz

