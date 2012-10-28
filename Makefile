all:
	valac-0.18 --enable-experimental -D GLIB_2_32 --pkg libsoup-2.4 --pkg gee-1.0 --pkg gtk+-3.0 --thread ./gmailicon.vala ./mailbox.vala ./feedcontroller.vala ./feed.vala --main=GmailFeed.main -o gmailnotify

