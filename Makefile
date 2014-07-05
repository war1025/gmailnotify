all: gmailnotify gmailsearch gmailhub

clean:
	rm -f ./gmailnotify
	rm -f ./gmailsearch
	rm -f ./gmailhub

gresource.c : gresource.xml $(shell glib-compile-resources --generate-dependencies gresource.xml)
	glib-compile-resources --generate-source ./gresource.xml

gmailnotify: feed.vala feedcontroller.vala mailbox.vala gmailicon.vala \
			dbus/interfaces.vala dbus/instance.vala gresource.c
	valac --enable-experimental -D GLIB_2_32 \
				--gresources ./gresource.xml \
				--target-glib=2.38 \
				--pkg libsecret-1 --pkg json-glib-1.0 --pkg libnotify \
				--pkg libsoup-2.4 --pkg gee-0.8 --pkg gtk+-3.0 --pkg posix --thread \
				./gmailicon.vala ./mailbox.vala ./feedcontroller.vala ./feed.vala \
				./dbus/interfaces.vala ./dbus/instance.vala \
				./gresource.c \
				--main=GmailFeed.main -o gmailnotify

gmailhub: dbus/interfaces.vala dbus/hub.vala
	valac --pkg gee-0.8 --pkg gio-2.0 \
				./dbus/interfaces.vala ./dbus/hub.vala \
				--main=GmailDbusHub.main -o gmailhub

gmailsearch: search-provider/gmailsearchprovider.vala dbus/interfaces.vala
	valac --pkg gio-2.0 --pkg gee-0.8 \
				./search-provider/gmailsearchprovider.vala ./dbus/interfaces.vala \
				--main=GmailSearchProvider.main -o gmailsearch

install-gmailnotify: gmailnotify gmailnotify.desktop install-images
	cp -f ./gmailnotify /usr/bin/
	cp ./gmailnotify.desktop /usr/share/applications/

uninstall-gmailnotify:
	rm -f /usr/bin/gmailnotify
	rm -f /usr/share/applications/gmailnotify.desktop
	rm -f /usr/share/pixmaps/gmailnotify.png

install-gmailhub: gmailhub dbus/org.wrowclif.GmailNotify.Hub.service
	cp -f ./gmailhub /usr/bin/gmailnotify-hub
	cp ./dbus/org.wrowclif.GmailNotify.Hub.service /usr/share/dbus-1/services/

uninstall-gmailhub:
	rm -f /usr/bin/gmailnotify-hub
	rm -f /usr/share/dbus-1/services/org.wrowclif.GmailNotify.Hub.service

restart-gmailhub:
	killall gmailnotify-hub

install-gmailsearch: gmailsearch search-provider/gmail-searchprovider.ini \
						search-provider/org.wrowclif.GmailSearch.service
	cp ./search-provider/gmail-searchprovider.ini /usr/share/gnome-shell/search-providers/
	cp ./search-provider/org.wrowclif.GmailSearch.service /usr/share/dbus-1/services/
	cp -f ./gmailsearch /usr/bin/gmail-searchprovider

uninstall-gmailsearch:
	rm -f /usr/share/gnome-shell/search-providers/gmail-searchprovider.ini
	rm -f /usr/share/dbus-1/services/org.wrowclif.GmailSearch.service
	rm -f /usr/bin/gmail-searchprovider

restart-gmailsearch:
	killall gmail-searchprovider

install-images: images/error.png images/mail.png images/nomail.png \
				images/important_full.png images/important_empty.png images/important_half.png \
				images/star_full.png images/star_empty.png images/star_half.png
	mkdir -p /usr/share/gmailnotify
	cp ./images/*png /usr/share/gmailnotify/
	cp ./images/mail.png /usr/share/pixmaps/gmailnotify.png
	cp ./images/nomail.png /usr/share/pixmaps/gmailnotify-empty.png
	cp ./images/error.png /usr/share/pixmaps/gmailnotify-error.png

uninstall-images:
	rm -rf /usr/share/gmailnotify
	rm -f /usr/share/pixmaps/gmailnotify.png

install-shell-extension: shell-extension/metadata.json shell-extension/extension.js
	mkdir -p ~/.local/share/gnome-shell/extensions/gmailnotify-indicator@wrowclif.org
	cp ./shell-extension/* ~/.local/share/gnome-shell/extensions/gmailnotify-indicator@wrowclif.org/
