all: gmailnotify gmailsearch

gmailnotify: feed.vala feedcontroller.vala mailbox.vala gmailicon.vala gmaildbus.vala
	valac-0.18 --enable-experimental -D GLIB_2_32 --pkg libsoup-2.4 --pkg gee-1.0 --pkg gtk+-3.0 --pkg posix --thread ./gmailicon.vala ./mailbox.vala ./feedcontroller.vala ./feed.vala ./gmaildbus.vala --main=GmailFeed.main -o gmailnotify

gmailsearch: gmailsearchprovider.vala
	valac-0.18 --pkg gio-2.0 --pkg gee-1.0 ./gmailsearchprovider.vala --main=GmailSearchProvider.main -o gmailsearch

install-gmailnotify: gmailnotify gmailnotify.desktop mail.png
	cp ./gmailnotify /usr/bin/
	cp ./gmailnotify.desktop /usr/share/applications/
	cp ./mail.png /usr/share/pixmaps/gmailnotify.png

uninstall-gmailnotify:
	rm -f /usr/bin/gmailnotify
	rm -f /usr/share/applications/gmailnotify.desktop
	rm -f /usr/share/pixmaps/gmailnotify.png

install-gmailsearch: gmailsearch gmail-searchprovider.ini org.wrowclif.GmailSearch.service
	cp ./gmail-searchprovider.ini /usr/share/gnome-shell/search-providers/
	cp ./org.wrowclif.GmailSearch.service /usr/share/dbus-1/services/
	cp ./gmailsearch /usr/bin/gmail-searchprovider

uninstall-gmailsearch:
	rm -f /usr/share/gnome-shell/search-providers/gmail-searchprovider.ini
	rm -f /usr/share/dbus-1/services/org.wrowclif.GmailSearch.service
	rm -f /usr/bin/gmail-searchprovider

restart-gmailsearch:
	killall gmail-searchprovider
